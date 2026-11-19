#include "copied_http.h"
#include <limits.h>
#include <pthread.h>
#include <stddef.h>
#include <string.h>

#define SESSION_COUNT 4
#define OP_COUNT 8
#define URL_CAP 2048
#define BODY_CAP 65536
/* No allocation failures or deferred callbacks: bounded process-local storage.
 * Invalidating an entry wipes copied payloads, but is not secure erasure. */
typedef struct {
    int32_t id,state,dispatched,url_length,max_response,status,error,length;
    uint8_t url[URL_CAP],body[BODY_CAP];
} operation;
typedef struct { int32_t id; operation ops[OP_COUNT]; } session;
static session sessions[SESSION_COUNT];
static pthread_mutex_t mutex=PTHREAD_MUTEX_INITIALIZER;
static int64_t next_session=1,next_operation=1;
static session *find_session(int32_t id) {
    if(id<=0)return NULL;
    for(int i=0;i<SESSION_COUNT;i++)if(sessions[i].id==id)return &sessions[i];
    return NULL;
}
static operation *find_op(session *s,int32_t id) {
    if(!s || id<=0)return NULL;
    for(int i=0;i<OP_COUNT;i++)if(s->ops[i].id==id)return &s->ops[i];
    return NULL;
}
static int valid_url(const uint8_t *url,int32_t n) {
    if(!url || n<1 || n>URL_CAP)return 0;
    int start=0;
    if(n>=8 && memcmp(url,"https://",8)==0)start=8;
    else if(n>=7 && memcmp(url,"http://",7)==0)start=7;
    else return 0;
    if(start==n || url[start]=='/' || url[start]=='?')return 0;
    int authority=1;
    for(int i=start;i<n;i++) {
        uint8_t c=url[i];
        if(c<33 || c>126 || c=='\\' || c=='#')return 0;
        if(c=='/' || c=='?')authority=0;
        if(authority && c=='@')return 0;
    }
    return 1;
}
int32_t mc_http_open(void) {
    pthread_mutex_lock(&mutex);
    int32_t answer=MC_HTTP_CAPACITY;
    for(int i=0;i<SESSION_COUNT;i++)if(!sessions[i].id) {
        if(next_session>INT32_MAX)answer=MC_HTTP_ID_EXHAUSTED;
        else { memset(&sessions[i],0,sizeof(session)); answer=sessions[i].id=(int32_t)next_session++; }
        break;
    }
    pthread_mutex_unlock(&mutex);return answer;
}
int32_t mc_http_close(int32_t id) {
    pthread_mutex_lock(&mutex);session *s=find_session(id);
    int32_t result=s?0:MC_HTTP_NOT_FOUND;
    if(s)memset(s,0,sizeof(*s));
    pthread_mutex_unlock(&mutex);return result;
}
int32_t mc_http_begin(int32_t id,const uint8_t *url,int32_t n,int32_t max_response) {
    if(!valid_url(url,n) || max_response<1 || max_response>BODY_CAP)return MC_HTTP_INVALID_ARGUMENT;
    pthread_mutex_lock(&mutex);session *s=find_session(id);int32_t answer=MC_HTTP_NOT_FOUND;
    if(s) {
        answer=MC_HTTP_CAPACITY;
        for(int i=0;i<OP_COUNT;i++)if(!s->ops[i].id) {
            if(next_operation>INT32_MAX)answer=MC_HTTP_ID_EXHAUSTED;
            else {
                operation *o=&s->ops[i];memset(o,0,sizeof(*o));
                answer=o->id=(int32_t)next_operation++;o->state=MC_HTTP_PENDING;
                o->url_length=n;o->max_response=max_response;memcpy(o->url,url,(size_t)n);
            }
            break;
        }
    }
    pthread_mutex_unlock(&mutex);return answer;
}
int32_t mc_http_next_request(int32_t id,int32_t *out_op,uint8_t *url,int32_t capacity,int32_t *out_length,int32_t *out_limit) {
    if(!out_op || !out_length || !out_limit || capacity<0 || (!url && capacity))return MC_HTTP_INVALID_ARGUMENT;
    *out_op=0;*out_length=0;*out_limit=0;
    pthread_mutex_lock(&mutex);session *s=find_session(id);int32_t answer=s?0:MC_HTTP_NOT_FOUND;
    operation *oldest=NULL;
    if(s)for(int i=0;i<OP_COUNT;i++) {
        operation *o=&s->ops[i];
        if(o->id && o->state==MC_HTTP_PENDING && !o->dispatched && (!oldest || o->id<oldest->id))oldest=o;
    }
    if(oldest) {
        *out_length=oldest->url_length;
        if(capacity<oldest->url_length)answer=MC_HTTP_BUFFER_TOO_SMALL;
        else { memcpy(url,oldest->url,(size_t)oldest->url_length);oldest->dispatched=1;*out_op=oldest->id;*out_limit=oldest->max_response;answer=1; }
    }
    pthread_mutex_unlock(&mutex);return answer;
}
int32_t mc_http_state(int32_t id,int32_t op) {
    pthread_mutex_lock(&mutex);operation *o=find_op(find_session(id),op);
    int32_t answer=o?o->state:MC_HTTP_NOT_FOUND;
    pthread_mutex_unlock(&mutex);return answer;
}
int32_t mc_http_complete(int32_t id,int32_t op,int32_t status,const uint8_t *body,int32_t n) {
    if(status<100 || status>599 || n<0 || (!body && n))return MC_HTTP_INVALID_ARGUMENT;
    pthread_mutex_lock(&mutex);operation *o=find_op(find_session(id),op);int32_t answer=MC_HTTP_NOT_FOUND;
    if(o) {
        answer=0;
        if(o->state==MC_HTTP_PENDING) {
            if(!o->dispatched)answer=MC_HTTP_INVALID_ARGUMENT;
            else {
                if(n>o->max_response) {o->state=MC_HTTP_FAILURE;o->error=MC_HTTP_ERROR_TOO_LARGE;}
                else {o->state=MC_HTTP_RESPONSE;o->status=status;o->length=n;if(n)memcpy(o->body,body,(size_t)n);}
                answer=1;
            }
        }
    }
    pthread_mutex_unlock(&mutex);return answer;
}
static int32_t terminal(int32_t id,int32_t op,int32_t state,int32_t error) {
    pthread_mutex_lock(&mutex);operation *o=find_op(find_session(id),op);int32_t answer=MC_HTTP_NOT_FOUND;
    if(o) {answer=0;if(o->state==MC_HTTP_PENDING){o->state=state;o->error=error;answer=1;}}
    pthread_mutex_unlock(&mutex);return answer;
}
int32_t mc_http_fail(int32_t id,int32_t op,int32_t error) {
    if(error<MC_HTTP_ERROR_IO || error>MC_HTTP_ERROR_TOO_LARGE)return MC_HTTP_INVALID_ARGUMENT;
    return terminal(id,op,MC_HTTP_FAILURE,error);
}
int32_t mc_http_cancel(int32_t id,int32_t op) {return terminal(id,op,MC_HTTP_CANCELLED,0);}
int32_t mc_http_poll(int32_t id,int32_t op,int32_t *state,int32_t *status,int32_t *error,
                     uint8_t *body,int32_t capacity,int32_t *length,int32_t consume) {
    if(!state || !status || !error || !length || capacity<0 || (!body && capacity) || (consume!=0 && consume!=1))return MC_HTTP_INVALID_ARGUMENT;
    *state=0;*status=0;*error=0;*length=0;
    pthread_mutex_lock(&mutex);operation *o=find_op(find_session(id),op);int32_t answer=MC_HTTP_NOT_FOUND;
    if(o) {
        *state=o->state;*status=o->status;*error=o->error;*length=o->length;
        if(o->state==MC_HTTP_PENDING)answer=0;
        else if(capacity<o->length)answer=MC_HTTP_BUFFER_TOO_SMALL;
        else {if(o->length)memcpy(body,o->body,(size_t)o->length);answer=1;if(consume)memset(o,0,sizeof(*o));}
    }
    pthread_mutex_unlock(&mutex);return answer;
}
