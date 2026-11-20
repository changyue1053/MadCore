/* Executes the actual production C bridge against deliberately simulated APIs. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "napi/native_api.h"
struct TestValue { napi_valuetype type; const char *bytes; size_t length; int64_t number; };
struct TestCall { size_t count; napi_value value; };
enum Fault { NONE, CB, TYPE, SIZE, COPY, MISMATCH, INT32, INT64, BOOL, DEFINE };
static enum Fault fault;
static napi_module *registered;
static napi_property_descriptor descriptors[3];
static struct TestValue result;
static const char *error;
static int native_result, native_calls;
static size_t native_length;
static char native_bytes[65536];
static void reset(void) { fault=NONE; error=NULL; native_result=1; native_calls=0; native_length=0; }
napi_status napi_throw_error(napi_env e,const char *code,const char *message) { (void)e; assert(code==NULL); error=message; return napi_ok; }
napi_status napi_create_int32(napi_env e,int32_t n,napi_value *out) { (void)e; if(fault==INT32)return napi_generic_failure; result.number=n; *out=&result; return napi_ok; }
napi_status napi_create_int64(napi_env e,int64_t n,napi_value *out) { (void)e; if(fault==INT64)return napi_generic_failure; result.number=n; *out=&result; return napi_ok; }
napi_status napi_get_cb_info(napi_env e,napi_callback_info c,size_t *count,napi_value *args,napi_value *self,void **data) { (void)e;(void)self;(void)data; if(fault==CB)return napi_generic_failure; size_t capacity=*count; for(size_t i=0;i<c->count && i<capacity;i++)args[i]=c->value; *count=c->count; return napi_ok; }
napi_status napi_typeof(napi_env e,napi_value v,napi_valuetype *out) { (void)e; if(fault==TYPE)return napi_generic_failure; *out=v->type; return napi_ok; }
napi_status napi_get_value_string_utf8(napi_env e,napi_value v,char *out,size_t capacity,size_t *length) { (void)e; if(!out){ if(fault==SIZE)return napi_generic_failure; *length=v->length; return napi_ok; } if(fault==COPY)return napi_generic_failure; assert(capacity==v->length+1); memcpy(out,v->bytes,v->length); out[v->length]=0; *length=fault==MISMATCH ? v->length+1 : v->length; return napi_ok; }
napi_status napi_get_boolean(napi_env e,int value,napi_value *out) { (void)e; if(fault==BOOL)return napi_generic_failure; result.number=value; *out=&result; return napi_ok; }
napi_status napi_define_properties(napi_env e,napi_value exports,size_t count,const napi_property_descriptor *p) { (void)e;(void)exports; if(fault==DEFINE)return napi_generic_failure; assert(count==3); memcpy(descriptors,p,sizeof descriptors); return napi_ok; }
void napi_module_register(napi_module *module) { assert(!registered); registered=module; }
int32_t madcore_abi_version(void) { return 1; }
int64_t madcore_epoch_millis(void) { return INT64_C(1700000000123); }
int32_t madcore_json_object_valid(const int8_t *bytes,int32_t length) { assert(length>0 && length<=65536); native_calls++; native_length=(size_t)length; memcpy(native_bytes,bytes,native_length); return native_result; }
#include "../../harmony/native/madcore_napi.c"
static napi_value json(struct TestValue *v,size_t count) { struct TestCall c={count,v}; return descriptors[2].method(NULL,&c); }
static void expect_error(napi_value v,const char *message) { assert(v==NULL); assert(error && strcmp(error,message)==0); }
int main(void) {
 reset(); assert(registered && registered->nm_version==1 && registered->nm_flags==0); assert(strcmp(registered->nm_modname,"madcore_napi")==0);
 struct TestValue exports={0}; assert(registered->nm_register_func(NULL,&exports)==&exports);
 const char *names[]={"abiVersion","epochMillis","isJsonObject"};
 for(int i=0;i<3;i++){ assert(strcmp(descriptors[i].utf8name,names[i])==0); assert(descriptors[i].method && !descriptors[i].getter && !descriptors[i].setter && !descriptors[i].data); }
 assert(descriptors[0].method(NULL,NULL)->number==1); assert(descriptors[1].method(NULL,NULL)->number==INT64_C(1700000000123));
 fault=INT32; expect_error(descriptors[0].method(NULL,NULL),"Core result failure"); reset(); fault=INT64; expect_error(descriptors[1].method(NULL,NULL),"Core result failure"); reset(); fault=DEFINE; expect_error(Init(NULL,&exports),"Core exports failure");
 struct TestValue input={napi_string,"{}",2,0};
 for(size_t count=0;count<5;count++){if(count==1)continue;reset();expect_error(json(&input,count),"Expected one JSON string");assert(native_calls==0);}
 reset();input.type=napi_number;expect_error(json(&input,1),"Expected one JSON string");input.type=napi_string;
 enum Fault input_faults[]={CB,TYPE,SIZE,COPY,MISMATCH};
 const char *messages[]={"Expected one JSON string","Expected one JSON string","JSON input exceeds limit","JSON input conversion failed","JSON input conversion failed"};
 for(size_t i=0;i<5;i++){reset();fault=input_faults[i];expect_error(json(&input,1),messages[i]);assert(native_calls==0);}
 reset(); assert(json(&input,1)->number==1 && native_calls==1); reset(); native_result=0; assert(json(&input,1)->number==0);
 reset();native_result=-1;expect_error(json(&input,1),"JSON input invalid");
 reset();fault=BOOL;expect_error(json(&input,1),"Core result failure");assert(native_calls==1);
 reset();input.bytes="";input.length=0;assert(json(&input,1)->number==0 && native_calls==0);
 static const char embedded[]={'{',0,'}'};reset();input.bytes=embedded;input.length=sizeof embedded;assert(json(&input,1)->number==1);assert(native_length==sizeof embedded && memcmp(native_bytes,embedded,sizeof embedded)==0);
 static char maximum[65536];memset(maximum,'x',sizeof maximum);reset();input.bytes=maximum;input.length=sizeof maximum;assert(json(&input,1)->number==1 && native_length==65536);
 reset();input.length=65537;expect_error(json(&input,1),"JSON input exceeds limit");assert(native_calls==0);
 puts("Actual C bridge host simulation passed; NOT Harmony NAPI/runtime or Kotlin validation");
 return 0;
}
