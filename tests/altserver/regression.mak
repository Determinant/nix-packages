include ../Makefile

regression: $(BUILD_DIR)/regression

# Main also owns utility functions used by the server objects. Rename only its
# entry point so the regression executable links the actual implementation.
$(BUILD_DIR)/regression-main.o: $(ROOT_DIR)/src/AltServerMain.cpp $(main_newfiles)
	$(CXX) $(CXXFLAGS) -I$(main_patched_root) -I$(ROOT_DIR)/src -include common.h $(INC_CFLAGS) -Dmain=altserver_unused_main -c $< -o $@

$(BUILD_DIR)/regression: $(filter-out %/src/AltServerMain.cpp.o,$(main_objs)) $(BUILD_DIR)/regression-main.o $(BUILD_DIR)/libimobiledevice.a $(BUILD_DIR)/AltSign.a $(BUILD_DIR)/libplist.a $(BUILD_DIR)/dnssd_loader.a
	$(CXX) $(CXXFLAGS) -I$(main_patched_root) -I$(ROOT_DIR)/src -include common.h $(INC_CFLAGS) ../regression.cpp -o $@ $^ $(LDFLAGS) -Wl,--wrap=idevice_connection_send -Wl,--wrap=idevice_connection_receive_timeout -Wl,--wrap=idevice_disconnect

device-regression: $(BUILD_DIR)/device-regression

DEVICE_WRAPS = idevice_new_with_options idevice_free lockdownd_client_new_with_handshake lockdownd_client_free lockdownd_start_service lockdownd_service_descriptor_free instproxy_client_new instproxy_client_free misagent_client_new misagent_client_free misagent_copy_all misagent_remove misagent_install misagent_get_status_code afc_client_new afc_client_free afc_get_file_info afc_make_directory afc_file_open afc_file_write afc_file_close instproxy_install

$(BUILD_DIR)/device-regression: $(filter-out %/src/AltServerMain.cpp.o,$(main_objs)) $(BUILD_DIR)/regression-main.o $(BUILD_DIR)/libimobiledevice.a $(BUILD_DIR)/AltSign.a $(BUILD_DIR)/libplist.a $(BUILD_DIR)/dnssd_loader.a
	$(CXX) $(CXXFLAGS) -I$(main_patched_root) -I$(ROOT_DIR)/src -include common.h $(INC_CFLAGS) ../device.cpp -o $@ $^ $(LDFLAGS) $(foreach symbol,$(DEVICE_WRAPS),-Wl,--wrap=$(symbol))
