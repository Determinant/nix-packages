#include "WirelessConnection.h"
#include "WiredConnection.h"
#include "ServerError.hpp"
#include "ProfilePolicy.h"
#include <cassert>
#include <future>
#include <thread>
#include <fcntl.h>
#include <sys/socket.h>
#include <unistd.h>

void expectFailure(pplx::task<std::vector<unsigned char>> task)
{
    try { task.get(); assert(false && "receive should fail"); }
    catch (const ServerError&) {}
}

namespace {
int wireMode = 0, disconnected = 0;
std::vector<unsigned char> sent;
}
extern "C" {
idevice_error_t __wrap_idevice_connection_send(idevice_connection_t, const char* data, uint32_t size, uint32_t* count) {
    *count = wireMode == 1 ? 0 : std::min(size, uint32_t(2));
    sent.insert(sent.end(), data, data + *count);
    return IDEVICE_E_SUCCESS;
}
idevice_error_t __wrap_idevice_connection_receive_timeout(idevice_connection_t, char* data, uint32_t size, uint32_t* count, unsigned int timeout) {
    assert(timeout == 60000);
    *count = wireMode ? 0 : std::min(size, uint32_t(2));
    std::fill(data, data + *count, 'x');
    return wireMode == 2 ? IDEVICE_E_TIMEOUT : IDEVICE_E_SUCCESS;
}
idevice_error_t __wrap_idevice_disconnect(idevice_connection_t) { ++disconnected; return IDEVICE_E_SUCCESS; }
}

int main()
{
    using namespace std::chrono_literals;
    std::set<std::string> active{"AltStore", "AltWidget", "S2Arm"};
    auto kept = ProfilesToPreserve(active, {"S2Arm"}, "S2Arm");
    assert(kept == active);
    kept = ProfilesToPreserve(std::set<std::string>{"AltStore", "NewApp"}, {"NewApp", "NewWidget"}, "NewApp");
    assert(kept->size() == 3 && kept->count("AltStore") && !kept->count("InactiveApp"));
    assert(!ProfilesToPreserve(std::nullopt, {"S2Arm"}, "S2Arm").has_value());
    assert(ProfilesToPreserve(active, {"Inactive"}, "Inactive")->empty());

    int sockets[2];
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) == 0);
    {
        WirelessConnection connection(sockets[0]);
        auto receiving = connection.ReceiveData(6);
        assert(send(sockets[1], "abc", 3, 0) == 3);
        std::this_thread::sleep_for(20ms);
        assert(send(sockets[1], "def", 3, 0) == 3);
        assert(receiving.get() == std::vector<unsigned char>({'a','b','c','d','e','f'}));
        assert(connection.ReceiveData(0).get().empty());
        expectFailure(connection.ReceiveData(-1));
        close(sockets[1]);
        expectFailure(connection.ReceiveData(4)); // EOF must not spin forever.
        std::vector<unsigned char> payload{1, 2};
        try { connection.SendData(payload).get(); assert(false); }
        catch (const ServerError&) {}
    }
    assert(fcntl(sockets[0], F_GETFD) == -1); // Derived destructor closes socket.

    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) == 0);
    {
        WirelessConnection connection(sockets[0]);
        int small = 1024;
        assert(setsockopt(sockets[0], SOL_SOCKET, SO_SNDBUF, &small, sizeof(small)) == 0);
        std::vector<unsigned char> payload(2 * 1024 * 1024);
        for (size_t i = 0; i < payload.size(); ++i) payload[i] = i % 251;
        auto reader = std::async(std::launch::async, [&]() {
            std::this_thread::sleep_for(30ms); // Force short writes / backpressure.
            std::vector<unsigned char> result;
            unsigned char buffer[777];
            while (result.size() < payload.size()) {
                auto n = recv(sockets[1], buffer, sizeof(buffer), 0);
                assert(n > 0);
                result.insert(result.end(), buffer, buffer + n);
            }
            return result;
        });
        connection.SendData(payload).get();
        assert(reader.get() == payload);
        close(sockets[1]);
    }
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) == 0);
    {
        WirelessConnection connection(sockets[0], 30ms);
        int small = 1024;
        assert(setsockopt(sockets[0], SOL_SOCKET, SO_SNDBUF, &small, sizeof(small)) == 0);
        char buffer[1024]{};
        while (send(sockets[0], buffer, sizeof(buffer), MSG_DONTWAIT | MSG_NOSIGNAL) > 0) {}
        auto response = web::json::value::object();
        auto start = std::chrono::steady_clock::now();
        try { connection.SendResponse(response).get(); assert(false); }
        catch (const ServerError&) {}
        assert(std::chrono::steady_clock::now() - start < 1s);
        // After the first timeout, later notifications must fail without another send.
        // Drain the peer: an accidental retry would succeed, making this assertion fail.
        while (recv(sockets[1], buffer, sizeof(buffer), MSG_DONTWAIT) > 0) {}
        try { connection.SendResponse(response).get(); assert(false); }
        catch (const ServerError&) {}
        close(sockets[1]);
    }
    {
        WiredConnection connection(nullptr, reinterpret_cast<idevice_connection_t>(1));
        assert(connection.ReceiveData(7).get() == std::vector<unsigned char>(7, 'x'));
        std::vector<unsigned char> payload{1,2,3,4,5};
        connection.SendData(payload).get();
        assert(sent == payload);
        wireMode = 1;
        expectFailure(connection.ReceiveData(1));
        try { connection.SendData(payload).get(); assert(false); }
        catch (const ServerError&) {}
        wireMode = 2;
        expectFailure(connection.ReceiveData(1));
        connection.Disconnect();
    }
    assert(disconnected == 1);
    puts("AltServer regression tests passed: profile policy, USB/Wi-Fi transport, EOF, backpressure, failed responses, cleanup");
}
