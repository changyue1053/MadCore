#include "madcore.h"
#include "napi/native_api.h"
#include <stdlib.h>

static napi_value Failure(napi_env env, const char* message) {
    napi_throw_error(env, NULL, message);
    return NULL;
}
static napi_value AbiVersion(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value result = NULL;
    if (napi_create_int32(env, madcore_abi_version(), &result) != napi_ok) return Failure(env, "Core result failure");
    return result;
}
static napi_value EpochMillis(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value result = NULL;
    if (napi_create_int64(env, madcore_epoch_millis(), &result) != napi_ok) return Failure(env, "Core result failure");
    return result;
}
static napi_value IsJsonObject(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2] = {NULL, NULL};
    napi_valuetype type;
    if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc != 1 ||
        napi_typeof(env, argv[0], &type) != napi_ok || type != napi_string) {
        return Failure(env, "Expected one JSON string");
    }
    size_t size = 0;
    if (napi_get_value_string_utf8(env, argv[0], NULL, 0, &size) != napi_ok || size > 65536) {
        return Failure(env, "JSON input exceeds limit");
    }
    // Bounded buffer includes NAPI terminator; the C API receives the actual byte length.
    char *bytes = (char *)malloc(size + 1);
    if (bytes == NULL) return Failure(env, "Core buffer allocation failed");
    size_t copied = 0;
    if (napi_get_value_string_utf8(env, argv[0], bytes, size + 1, &copied) != napi_ok || copied != size) {
        free(bytes);
        return Failure(env, "JSON input conversion failed");
    }
    const int valid = size == 0 ? 0 : madcore_json_object_valid((const int8_t*)bytes, (int32_t)size);
    free(bytes);
    if (valid < 0) return Failure(env, "JSON input invalid");
    napi_value result = NULL;
    if (napi_get_boolean(env, valid == 1, &result) != napi_ok) return Failure(env, "Core result failure");
    return result;
}
extern int32_t madcore_copied_http_link_probe(void);
static napi_value CopiedProbe(napi_env env, napi_callback_info info) {
    (void)info; napi_value result = NULL;
    if (napi_create_int32(env, madcore_copied_http_link_probe(), &result) != napi_ok) return Failure(env, "Probe result failure");
    return result;
}
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor properties[] = {
        {"copiedProbe", NULL, CopiedProbe, NULL, NULL, NULL, napi_default, NULL},
        {"abiVersion", NULL, AbiVersion, NULL, NULL, NULL, napi_default, NULL},
        {"epochMillis", NULL, EpochMillis, NULL, NULL, NULL, napi_default, NULL},
        {"isJsonObject", NULL, IsJsonObject, NULL, NULL, NULL, napi_default, NULL}
    };
    if (napi_define_properties(env, exports, 4, properties) != napi_ok) return Failure(env, "Core exports failure");
    return exports;
}
static napi_module module = {1, 0, NULL, Init, "madcore_napi", NULL, {0}};
__attribute__((constructor)) void RegisterMadCore(void) { napi_module_register(&module); }
