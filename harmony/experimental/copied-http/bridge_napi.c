/* Experimental owner-environment boundary. No native async work, retained Kotlin
 * objects or borrowed payload pointers. Cleanup only closes C-owned numeric IDs. */
#include "madcore.h"
#include "copied_http.h"
#include "napi/native_api.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct { napi_env owner; int32_t sessions[4]; } bridge_env;
extern int32_t madcore_copied_http_test_start(int32_t,const int8_t*,int32_t,int32_t);
extern int32_t madcore_copied_http_test_poll(int32_t,int32_t,int32_t);
extern int32_t madcore_copied_http_test_cancel(int32_t,int32_t);
static napi_value error(napi_env e) { napi_throw_error(e,NULL,"Copied HTTP boundary failure");return NULL; }
static napi_value number(napi_env e,int32_t n) { napi_value v=NULL;return napi_create_int32(e,n,&v)==napi_ok?v:error(e); }
static int integer(napi_env e,napi_value v,int32_t *n) {
    napi_valuetype t;double d;
    if(napi_typeof(e,v,&t)!=napi_ok || t!=napi_number || napi_get_value_double(e,v,&d)!=napi_ok || !(d>=0 && d<=2147483647.0))return 0;
    *n=(int32_t)d;return d==(double)*n;
}
static bridge_env *arguments(napi_env e,napi_callback_info i,size_t expected,napi_value *v) {
    size_t n=expected+1;void *data=NULL;
    if(napi_get_cb_info(e,i,&n,v,NULL,&data)!=napi_ok || n!=expected || !data)return NULL;
    bridge_env *b=data;return b->owner==e?b:NULL;
}
static int owns(bridge_env *b,int32_t s) { for(int i=0;i<4;i++)if(s>0 && b->sessions[i]==s)return 1;return 0; }
static int field(napi_env e,napi_value object,const char *name,napi_value value) { return napi_set_named_property(e,object,name,value)==napi_ok; }
static int intfield(napi_env e,napi_value o,const char *name,int32_t n) { napi_value v=NULL;return napi_create_int32(e,n,&v)==napi_ok && field(e,o,name,v); }
static int strfield(napi_env e,napi_value o,const char *name,const uint8_t *s,int32_t n) {
    napi_value v=NULL;return napi_create_string_utf8(e,(const char*)s,(size_t)n,&v)==napi_ok && field(e,o,name,v);
}
static int bytesfield(napi_env e,napi_value o,const char *name,const uint8_t *s,int32_t n) {
    napi_value v=NULL;void *p=NULL;if(napi_create_arraybuffer(e,(size_t)n,&p,&v)!=napi_ok)return 0;
    if(n)memcpy(p,s,(size_t)n);return field(e,o,name,v);
}
static void cleanup(void *data) {
    bridge_env *b=data;for(int i=0;i<4;i++)if(b->sessions[i]>0)mc_http_close(b->sessions[i]);
    memset(b,0,sizeof(*b));free(b);
}
static napi_value Open(napi_env e,napi_callback_info info) {
    napi_value a[1];bridge_env *b=arguments(e,info,0,a);if(!b)return error(e);
    int slot=-1;for(int i=0;i<4;i++)if(!b->sessions[i]){slot=i;break;}
    if(slot<0)return number(e,MC_HTTP_CAPACITY);
    int32_t s=mc_http_open();if(s>0)b->sessions[slot]=s;
    napi_value out=NULL;if(napi_create_int32(e,s,&out)!=napi_ok){if(s>0){mc_http_close(s);b->sessions[slot]=0;}return error(e);}return out;
}
static napi_value Close(napi_env e,napi_callback_info info) {
    napi_value a[2];bridge_env *b=arguments(e,info,1,a);int32_t s;
    if(!b || !integer(e,a[0],&s))return error(e);
    if(!owns(b,s))return number(e,MC_HTTP_NOT_FOUND);
    for(int i=0;i<4;i++)if(b->sessions[i]==s)b->sessions[i]=0;
    return number(e,mc_http_close(s));
}
static napi_value State(napi_env e,napi_callback_info info) {
    napi_value a[3];bridge_env *b=arguments(e,info,2,a);int32_t s,o;
    if(!b || !integer(e,a[0],&s)||!integer(e,a[1],&o))return error(e);
    return number(e,owns(b,s)?mc_http_state(s,o):MC_HTTP_NOT_FOUND);
}
static napi_value Next(napi_env e,napi_callback_info info) {
    napi_value a[2];bridge_env *b=arguments(e,info,1,a);int32_t s;
    if(!b || !integer(e,a[0],&s)||!owns(b,s))return error(e);
    struct mc_http_request *r=calloc(1,sizeof(*r));if(!r)return error(e);
    int32_t id=0;int code=mc_http_next_request_v2(s,&id,r);napi_value out=NULL;
    if(code==0){free(r);return napi_get_null(e,&out)==napi_ok?out:error(e);}
    if(code!=1 || napi_create_object(e,&out)!=napi_ok){if(code==1)mc_http_fail(s,id,MC_HTTP_ERROR_IO);free(r);return error(e);}
    int ok=intfield(e,out,"operation",id)&&intfield(e,out,"method",r->method)&&
        strfield(e,out,"url",r->url,r->url_length)&&strfield(e,out,"headers",r->headers,r->headers_length)&&
        bytesfield(e,out,"body",r->body,r->body_length)&&intfield(e,out,"maxResponse",r->max_response)&&
        intfield(e,out,"connectTimeout",r->connect_timeout_ms)&&intfield(e,out,"readTimeout",r->read_timeout_ms)&&
        intfield(e,out,"callTimeout",r->call_timeout_ms)&&intfield(e,out,"allowInsecure",r->allow_insecure);
    free(r);if(!ok){mc_http_fail(s,id,MC_HTTP_ERROR_IO);return error(e);}return out;
}
static napi_value Complete(napi_env e,napi_callback_info info) {
    napi_value a[6];bridge_env *b=arguments(e,info,5,a);int32_t s,o,status;
    if(!b||!integer(e,a[0],&s)||!integer(e,a[1],&o)||!integer(e,a[2],&status))return error(e);
    if(!owns(b,s))return number(e,MC_HTTP_NOT_FOUND);
    struct mc_http_response *r=calloc(1,sizeof(*r));if(!r)return error(e);
    size_t n=0,copied=0,body_n=0;void *body=NULL;napi_valuetype t;
    if(napi_typeof(e,a[3],&t)!=napi_ok||t!=napi_string||napi_get_value_string_utf8(e,a[3],NULL,0,&n)!=napi_ok||
       napi_get_arraybuffer_info(e,a[4],&body,&body_n)!=napi_ok||(body_n>0 && body==NULL)){free(r);return number(e,mc_http_fail(s,o,MC_HTTP_ERROR_IO));}
    if(n>16384||body_n>65536){free(r);return number(e,mc_http_fail(s,o,MC_HTTP_ERROR_TOO_LARGE));}
    /* NAPI string copy needs one terminator byte; use a separate bounded buffer. */
    char headers[16385];
    if(napi_get_value_string_utf8(e,a[3],headers,sizeof(headers),&copied)!=napi_ok||copied!=n){mc_http_fail(s,o,MC_HTTP_ERROR_IO);free(r);return error(e);}
    r->status=status;r->headers_length=(int32_t)n;memcpy(r->headers,headers,n);
    r->body_length=(int32_t)body_n;if(body_n)memcpy(r->body,body,body_n);
    int code=mc_http_complete_response(s,o,r);free(r);return number(e,code);
}
static napi_value Fail(napi_env e,napi_callback_info info) {
    napi_value a[4];bridge_env *b=arguments(e,info,3,a);int32_t s,o,f;
    if(!b||!integer(e,a[0],&s)||!integer(e,a[1],&o)||!integer(e,a[2],&f))return error(e);
    return number(e,owns(b,s)?mc_http_fail(s,o,f):MC_HTTP_NOT_FOUND);
}
static napi_value StartTest(napi_env e,napi_callback_info info) {
    napi_value a[4];bridge_env *b=arguments(e,info,3,a);int32_t s,scenario;size_t n=0,copied=0;napi_valuetype t;
    if(!b||!integer(e,a[0],&s)||!owns(b,s)||!integer(e,a[2],&scenario)||napi_typeof(e,a[1],&t)!=napi_ok||t!=napi_string||
       napi_get_value_string_utf8(e,a[1],NULL,0,&n)!=napi_ok||n<1||n>2048)return error(e);
    char url[2049];if(napi_get_value_string_utf8(e,a[1],url,sizeof(url),&copied)!=napi_ok||copied!=n)return error(e);
    return number(e,madcore_copied_http_test_start(s,(const int8_t*)url,(int32_t)n,scenario));
}
static napi_value PollTest(napi_env e,napi_callback_info info) {
    napi_value a[4];bridge_env *b=arguments(e,info,3,a);int32_t s,o,scenario;
    if(!b||!integer(e,a[0],&s)||!integer(e,a[1],&o)||!integer(e,a[2],&scenario))return error(e);
    return number(e,owns(b,s)?madcore_copied_http_test_poll(s,o,scenario):MC_HTTP_NOT_FOUND);
}
static napi_value CancelTest(napi_env e,napi_callback_info info) {
    napi_value a[3];bridge_env *b=arguments(e,info,2,a);int32_t s,o;
    if(!b||!integer(e,a[0],&s)||!integer(e,a[1],&o))return error(e);
    return number(e,owns(b,s)?madcore_copied_http_test_cancel(s,o):MC_HTTP_NOT_FOUND);
}
static napi_value Init(napi_env e,napi_value exports) {
    bridge_env *b=calloc(1,sizeof(*b));if(!b)return error(e);b->owner=e;
    if(napi_add_env_cleanup_hook(e,cleanup,b)!=napi_ok){free(b);return error(e);}
    napi_property_descriptor p[]={
        {"open",NULL,Open,NULL,NULL,NULL,napi_default,b},{"close",NULL,Close,NULL,NULL,NULL,napi_default,b},
        {"state",NULL,State,NULL,NULL,NULL,napi_default,b},{"nextRequest",NULL,Next,NULL,NULL,NULL,napi_default,b},
        {"complete",NULL,Complete,NULL,NULL,NULL,napi_default,b},{"fail",NULL,Fail,NULL,NULL,NULL,napi_default,b},
        {"startTest",NULL,StartTest,NULL,NULL,NULL,napi_default,b},{"pollTest",NULL,PollTest,NULL,NULL,NULL,napi_default,b},
        {"cancelTest",NULL,CancelTest,NULL,NULL,NULL,napi_default,b}};
    if(napi_define_properties(e,exports,sizeof(p)/sizeof(p[0]),p)!=napi_ok)return error(e);
    return exports;
}
static napi_module module={1,0,NULL,Init,"madcore_copied_bridge",NULL,{0}};
__attribute__((constructor)) void RegisterCopiedBridge(void){napi_module_register(&module);}
