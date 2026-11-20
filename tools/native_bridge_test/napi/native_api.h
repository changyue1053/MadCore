#ifndef MADCORE_TEST_NAPI_H
#define MADCORE_TEST_NAPI_H
/* Host test double only. Not Huawei headers and never shipped in the HAR. */
#include <stddef.h>
#include <stdint.h>
typedef void *napi_env;
typedef struct TestValue *napi_value;
typedef struct TestCall *napi_callback_info;
typedef enum { napi_ok, napi_generic_failure } napi_status;
typedef enum { napi_undefined, napi_string, napi_number, napi_boolean } napi_valuetype;
typedef napi_value (*napi_callback)(napi_env, napi_callback_info);
typedef enum { napi_default = 0 } napi_property_attributes;
typedef struct { const char *utf8name; napi_value name; napi_callback method, getter, setter; napi_value value; napi_property_attributes attributes; void *data; } napi_property_descriptor;
typedef struct { int nm_version; unsigned nm_flags; const char *nm_filename; napi_value (*nm_register_func)(napi_env,napi_value); const char *nm_modname; void *nm_priv; void *reserved[4]; } napi_module;
napi_status napi_throw_error(napi_env,const char*,const char*);
napi_status napi_create_int32(napi_env,int32_t,napi_value*);
napi_status napi_create_int64(napi_env,int64_t,napi_value*);
napi_status napi_get_cb_info(napi_env,napi_callback_info,size_t*,napi_value*,napi_value*,void**);
napi_status napi_typeof(napi_env,napi_value,napi_valuetype*);
napi_status napi_get_value_string_utf8(napi_env,napi_value,char*,size_t,size_t*);
napi_status napi_get_boolean(napi_env,int,napi_value*);
napi_status napi_define_properties(napi_env,napi_value,size_t,const napi_property_descriptor*);
void napi_module_register(napi_module*);
#endif
