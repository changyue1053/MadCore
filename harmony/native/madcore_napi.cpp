#include "madcore.h"
#include "napi/native_api.h"
#include <string>

namespace {
napi_value Failure(napi_env env, const char* message) {
    napi_throw_error(env, nullptr, message);
    return nullptr;
}
napi_value AbiVersion(napi_env env, napi_callback_info) {
    napi_value result = nullptr;
    if (napi_create_int32(env, madcore_abi_version(), &result) != napi_ok) return Failure(env, "Core result failure");
    return result;
}
napi_value EpochMillis(napi_env env, napi_callback_info) {
    napi_value result = nullptr;
    if (napi_create_int64(env, madcore_epoch_millis(), &result) != napi_ok) return Failure(env, "Core result failure");
    return result;
}
napi_value IsJsonObject(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2] = {nullptr, nullptr};
    napi_valuetype type;
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc != 1 ||
        napi_typeof(env, argv[0], &type) != napi_ok || type != napi_string) {
        return Failure(env, "Expected one JSON string");
    }
    size_t size = 0;
    if (napi_get_value_string_utf8(env, argv[0], nullptr, 0, &size) != napi_ok || size > 65536) {
        return Failure(env, "JSON input exceeds limit");
    }
    // Bounded buffer includes NAPI terminator; the C API receives the actual byte length.
    std::string bytes(size + 1, '\0');
    size_t copied = 0;
    if (napi_get_value_string_utf8(env, argv[0], &bytes[0], bytes.size(), &copied) != napi_ok || copied != size) {
        return Failure(env, "JSON input conversion failed");
    }
    const int valid = size == 0 ? 0 : madcore_json_object_valid(reinterpret_cast<const int8_t*>(bytes.data()), static_cast<int32_t>(size));
    if (valid < 0) return Failure(env, "JSON input invalid");
    napi_value result = nullptr;
    if (napi_get_boolean(env, valid == 1, &result) != napi_ok) return Failure(env, "Core result failure");
    return result;
}
napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor properties[] = {
        {"abiVersion", nullptr, AbiVersion, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"epochMillis", nullptr, EpochMillis, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"isJsonObject", nullptr, IsJsonObject, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    if (napi_define_properties(env, exports, 3, properties) != napi_ok) return Failure(env, "Core exports failure");
    return exports;
}
napi_module module = {1, 0, nullptr, Init, "madcore_napi", nullptr, {0}};
}
extern "C" __attribute__((constructor)) void RegisterMadCore() { napi_module_register(&module); }
