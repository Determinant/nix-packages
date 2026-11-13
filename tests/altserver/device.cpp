// Exercises the production installation transaction; only the device C API is mocked.
#include "DeviceManager.hpp"
#include "ServerError.hpp"
#include "ClientConnection.h"
#include <libimobiledevice/lockdown.h>
#include <libimobiledevice/installation_proxy.h>
#include <atomic>
#include <cassert>
#include <filesystem>
#include <thread>
#include <stdexcept>
#include <fstream>
#include <cstring>

namespace {
using Profile = std::shared_ptr<ProvisioningProfile>;
std::vector<Profile> profiles;
std::vector<std::string> removed;
Profile incoming;
std::thread worker;
std::atomic<bool> stop{false};
int workers = 0;
int misStatus = 0;
std::string mode;
std::string fixtures;

template<class T> T fake() { return reinterpret_cast<T>(1); }
std::set<std::string> installed() {
    std::set<std::string> result;
    for (auto& p : profiles) result.insert(p->bundleIdentifier());
    return result;
}
void add(Profile p) {
    profiles.erase(std::remove_if(profiles.begin(), profiles.end(), [&](Profile old) {
        return old->bundleIdentifier() == p->bundleIdentifier();
    }), profiles.end());
    profiles.push_back(p);
}
void reset() {
    assert(!worker.joinable() && workers == 0);
    profiles.clear(); removed.clear(); stop = false;
    for (auto name : {"A", "B", "C"})
        profiles.push_back(std::make_shared<ProvisioningProfile>(fixtures + "/" + name + ".mobileprovision"));
}
void status(instproxy_status_cb_t cb, void* context, const char* state, int percent,
            const char* error = nullptr) {
    plist_t p = plist_new_dict();
    plist_dict_set_item(p, "Status", plist_new_string(state));
    if (percent >= 0) plist_dict_set_item(p, "PercentComplete", plist_new_uint(percent));
    if (error) {
        plist_dict_set_item(p, "Error", plist_new_string(error));
        plist_dict_set_item(p, "ErrorDescription", plist_new_string("simulated failure"));
        plist_dict_set_item(p, "ErrorDetail", plist_new_uint(42));
    }
    cb(nullptr, p, context);
    plist_free(p);
}
}

extern "C" {
idevice_error_t __wrap_idevice_new_with_options(idevice_t* p, const char*, enum idevice_options) { *p = fake<idevice_t>(); return IDEVICE_E_SUCCESS; }
idevice_error_t __wrap_idevice_free(idevice_t) { return IDEVICE_E_SUCCESS; }
lockdownd_error_t __wrap_lockdownd_client_new_with_handshake(idevice_t, lockdownd_client_t* p, const char*) { *p = fake<lockdownd_client_t>(); return LOCKDOWN_E_SUCCESS; }
lockdownd_error_t __wrap_lockdownd_client_free(lockdownd_client_t) { return LOCKDOWN_E_SUCCESS; }
lockdownd_error_t __wrap_lockdownd_start_service(lockdownd_client_t, const char*, lockdownd_service_descriptor_t* p) { *p = fake<lockdownd_service_descriptor_t>(); return LOCKDOWN_E_SUCCESS; }
lockdownd_error_t __wrap_lockdownd_service_descriptor_free(lockdownd_service_descriptor_t) { return LOCKDOWN_E_SUCCESS; }
instproxy_error_t __wrap_instproxy_client_new(idevice_t, lockdownd_service_descriptor_t, instproxy_client_t* p) { *p = fake<instproxy_client_t>(); return INSTPROXY_E_SUCCESS; }
instproxy_error_t __wrap_instproxy_client_free(instproxy_client_t) {
    stop = true;
    if (worker.joinable()) { worker.join(); --workers; }
    return INSTPROXY_E_SUCCESS;
}
misagent_error_t __wrap_misagent_client_new(idevice_t, lockdownd_service_descriptor_t, misagent_client_t* p) { *p = fake<misagent_client_t>(); return MISAGENT_E_SUCCESS; }
misagent_error_t __wrap_misagent_client_free(misagent_client_t) { return MISAGENT_E_SUCCESS; }
misagent_error_t __wrap_misagent_copy_all(misagent_client_t, plist_t* p) {
    *p = plist_new_array();
    for (auto& profile : profiles) {
        auto bytes = profile->data();
        plist_array_append_item(*p, plist_new_data((const char*)bytes.data(), bytes.size()));
    }
    return MISAGENT_E_SUCCESS;
}
misagent_error_t __wrap_misagent_remove(misagent_client_t, const char* uuid) {
    if (mode == "remove-error" && removed.size() == 1) {
        misStatus = -1; return MISAGENT_E_REQUEST_FAILED;
    }
    for (auto it = profiles.begin(); it != profiles.end(); ++it) if ((*it)->uuid() == uuid) {
        removed.push_back((*it)->bundleIdentifier()); profiles.erase(it); return MISAGENT_E_SUCCESS;
    }
    misStatus = -402620405;
    return MISAGENT_E_REQUEST_FAILED;
}
misagent_error_t __wrap_misagent_install(misagent_client_t, plist_t p) {
    char* bytes = nullptr; uint64_t size = 0; plist_get_data_val(p, &bytes, &size);
    std::vector<unsigned char> data(bytes, bytes + size); free(bytes);
    add(std::make_shared<ProvisioningProfile>(data));
    assert(installed().size() <= 3);
    return MISAGENT_E_SUCCESS;
}
int __wrap_misagent_get_status_code(misagent_client_t) { return misStatus; }
afc_error_t __wrap_afc_client_new(idevice_t, lockdownd_service_descriptor_t, afc_client_t* p) { *p = fake<afc_client_t>(); return AFC_E_SUCCESS; }
afc_error_t __wrap_afc_client_free(afc_client_t) { return AFC_E_SUCCESS; }
afc_error_t __wrap_afc_get_file_info(afc_client_t, const char*, char*** p) { *p = nullptr; return AFC_E_SUCCESS; }
afc_error_t __wrap_afc_make_directory(afc_client_t, const char*) { return AFC_E_SUCCESS; }
afc_error_t __wrap_afc_file_open(afc_client_t, const char*, afc_file_mode_t, uint64_t* p) { *p = 1; return AFC_E_SUCCESS; }
afc_error_t __wrap_afc_file_write(afc_client_t, uint64_t, const char*, uint32_t n, uint32_t* p) { *p = mode == "zero-write" ? 0 : n; return AFC_E_SUCCESS; }
afc_error_t __wrap_afc_file_close(afc_client_t, uint64_t) { return AFC_E_SUCCESS; }
instproxy_error_t __wrap_instproxy_install(instproxy_client_t, const char*, plist_t,
                                          instproxy_status_cb_t cb, void* context) {
    if (mode == "immediate-error") return INSTPROXY_E_CONN_FAILED;
    stop = false; ++workers;
    worker = std::thread([=] {
        using namespace std::chrono_literals;
        if (mode == "timeout") { while (!stop) std::this_thread::sleep_for(1ms); return; }
        if (mode == "first-error") { status(cb, context, "Error", -1, "ApplicationVerificationFailed"); return; }
        if (mode == "first-complete") { add(incoming); status(cb, context, "Complete", -1); return; }
        auto next = installed(); next.insert(incoming->bundleIdentifier());
        if (next.size() > 3) { status(cb, context, "Error", -1, "MaximumFreeAppLimitReached"); return; }
        status(cb, context, "CreatingStagingDirectory", 0);
        status(cb, context, "Installing", 50);
        if (mode == "progress-error") { while (!stop) std::this_thread::sleep_for(1ms); return; }
        if (mode == "heartbeat") {
            for (int i = 0; i < 8; ++i) {
                std::this_thread::sleep_for(10ms);
                status(cb, context, "Installing", 60 + i);
            }
        }
        status(cb, context, "Installing", 100);
        add(incoming);
        status(cb, context, "Complete", -1);
    });
    return INSTPROXY_E_SUCCESS;
}
}

// Exercise the public protocol through the real ClientConnection implementation.
// In particular, 100% must not be sent before profiles are restored and the
// installation worker has joined.
class MemoryConnection : public ClientConnection {
public:
    std::vector<unsigned char> input;
    size_t offset = 0;
    std::vector<web::json::value> responses;
    void append(web::json::value json) {
        auto body = json.serialize();
        int32_t size = body.size();
        auto length = reinterpret_cast<unsigned char*>(&size);
        input.insert(input.end(), length, length + sizeof(size));
        input.insert(input.end(), body.begin(), body.end());
    }
    pplx::task<std::vector<unsigned char>> ReceiveData(int size) override {
        assert(size >= 0 && offset + size <= input.size());
        std::vector<unsigned char> data(input.begin() + offset, input.begin() + offset + size);
        offset += size;
        return pplx::task_from_result(data);
    }
    pplx::task<void> SendData(std::vector<unsigned char>& data) override {
        int32_t size = 0;
        std::memcpy(&size, data.data(), sizeof(size));
        assert(size + sizeof(size) == data.size());
        auto json = web::json::value::parse(std::string(data.begin() + sizeof(size), data.end()));
        if (json.has_field("progress") && json["progress"].as_double() == 1.0) {
            assert(workers == 0 && !worker.joinable());
            assert(installed() == std::set<std::string>({"A", "B", "C"}));
        }
        responses.push_back(json);
        return pplx::task_from_result();
    }
};

int main(int argc, char** argv) {
    assert(argc == 2); fixtures = argv[1];
    const std::set<std::string> active{"A", "B", "C"};
    auto run = [&](const char* scenario, const char* app, bool fail) {
        reset(); mode = scenario;
        incoming = std::make_shared<ProvisioningProfile>(fixtures + "/" + app + ".app/embedded.mobileprovision");
        bool failed = false;
        auto start = std::chrono::steady_clock::now();
        try {
            DeviceManager::instance()->InstallApp(fixtures + "/" + app + ".app", "MOCK", active,
                [&](double progress) {
                    assert(progress < 1.0);
                    if (mode == "progress-error" && progress > 0.75) throw std::runtime_error("send failed");
                    if (mode == "upload-error") throw std::runtime_error("upload response failed");
                }, std::chrono::milliseconds(40)).get();
        } catch (const std::exception&) { failed = true; }
        assert(failed == fail);
        assert(workers == 0 && !worker.joinable());
        assert(installed() == active);
        if (std::string(app) == "A") assert(removed.empty());
        else assert(!removed.empty());
        assert(std::chrono::steady_clock::now() - start < std::chrono::seconds(2));
        printf("Installation transaction passed: %s, app=%s\n", scenario, app);
    };
    run("success", "A", false);
    run("success", "D", false); // Full slots: install as inactive, restore all active apps.
    run("first-error", "D", true);
    run("immediate-error", "D", true);
    run("timeout", "D", true);
    run("progress-error", "D", true);
    run("upload-error", "A", true);
    run("zero-write", "A", true);
    run("remove-error", "D", true);
    run("first-complete", "A", false);
    run("heartbeat", "A", false); // Progress extends the inactivity deadline.
    run("success", "A", false); // The same manager's installation mutex remains usable.

    for (auto scenario : {"success", "first-error"}) {
        reset(); mode = scenario;
        incoming = std::make_shared<ProvisioningProfile>(fixtures + "/D.app/embedded.mobileprovision");
        std::ifstream file(fixtures + "/D.ipa", std::ios::binary);
        std::vector<unsigned char> ipa((std::istreambuf_iterator<char>(file)), {});
        assert(!ipa.empty());
        MemoryConnection connection;
        auto prepare = web::json::value::object();
        prepare["identifier"] = web::json::value::string("PrepareAppRequest");
        prepare["udid"] = web::json::value::string("MOCK");
        prepare["contentSize"] = web::json::value::number((int)ipa.size());
        connection.append(prepare);
        connection.input.insert(connection.input.end(), ipa.begin(), ipa.end());
        connection.append(web::json::value::parse("{\"identifier\":\"BeginInstallationRequest\",\"activeProfiles\":[\"A\",\"B\",\"C\"]}"));
        bool failed = false;
        try { connection.ProcessAppRequest().get(); }
        catch (const std::exception&) { failed = true; }
        assert(failed == (mode == "first-error"));
        assert(!connection.responses.empty());
        auto last = connection.responses.back();
        if (failed) {
            assert(last["identifier"].as_string() == "ErrorResponse");
            for (auto& response : connection.responses)
                if (response.has_field("progress")) assert(response["progress"].as_double() < 1.0);
        } else assert(last["progress"].as_double() == 1.0);
        assert(workers == 0 && installed() == active);
        printf("Installation protocol passed: %s\n", scenario);
    }
}
