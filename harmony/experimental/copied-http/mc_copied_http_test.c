/* Same translation unit only to force near-exhaustion counters in host tests.
 * Production builds compile copied_http.c independently, with no reset API. */
#include "copied_http.c"
#include <assert.h>
#include <stdio.h>
static const uint8_t URL[]="https://example.invalid/path";
static int32_t begin(int32_t s,int32_t cap) {return mc_http_begin(s,URL,(int32_t)sizeof(URL)-1,cap);}
static void dispatch(int32_t s,int32_t expected) {
    uint8_t url[2048];int32_t op=0,n=0,limit=0;
    assert(mc_http_next_request(s,&op,url,sizeof(url),&n,&limit)==1);
    assert(limit==8);
    assert(op==expected && n==(int32_t)sizeof(URL)-1 && memcmp(url,URL,(size_t)n)==0);
}
static int32_t read_result(int32_t s,int32_t op,int32_t expected,int consume) {
    uint8_t bytes[65536];int32_t state,status,error,n;
    assert(mc_http_poll(s,op,&state,&status,&error,bytes,sizeof(bytes),&n,consume)==1);
    assert(state==expected);return error;
}
static void *race_complete(void *arg) {int32_t *v=arg;v[2]=mc_http_complete(v[0],v[1],200,(const uint8_t*)"ok",2);return NULL;}
static void *race_cancel(void *arg) {int32_t *v=arg;v[3]=mc_http_cancel(v[0],v[1]);return NULL;}
typedef struct {
    pthread_mutex_t gate;
    pthread_cond_t ready;
    int arrivals;
    int32_t session,op,complete_result,poll_result,close_result;
    int32_t state,status,error,length;
    uint8_t body[8];
} close_race;
static void synchronize(close_race *r) {
    assert(pthread_mutex_lock(&r->gate)==0);
    r->arrivals++;
    if(r->arrivals==3)assert(pthread_cond_broadcast(&r->ready)==0);
    while(r->arrivals<3)assert(pthread_cond_wait(&r->ready,&r->gate)==0);
    assert(pthread_mutex_unlock(&r->gate)==0);
}
static void *close_racer(void *arg) {
    close_race *r=arg;synchronize(r);r->close_result=mc_http_close(r->session);return NULL;
}
static void *complete_racer(void *arg) {
    close_race *r=arg;synchronize(r);
    r->complete_result=mc_http_complete(r->session,r->op,201,(const uint8_t*)"race",4);return NULL;
}
static void *poll_racer(void *arg) {
    close_race *r=arg;synchronize(r);
    r->poll_result=mc_http_poll(r->session,r->op,&r->state,&r->status,&r->error,
                              r->body,sizeof(r->body),&r->length,1);return NULL;
}
static void test_v2(void) {
    int32_t s=mc_http_open(),op,out,state,error,n,limit;uint8_t legacy_url[2048];
    struct mc_http_request r={0},received;
    struct mc_http_response response={0},result;
    r.method=MC_HTTP_POST;r.url_length=(int32_t)sizeof(URL)-1;memcpy(r.url,URL,sizeof(URL)-1);
    r.headers_length=9;memcpy(r.headers,"{\"x\":\"y\"}",9);
    r.body_length=3;memcpy(r.body,"a\0b",3);r.max_response=8;
    r.connect_timeout_ms=1;r.read_timeout_ms=120000;r.call_timeout_ms=120000;
    assert(mc_http_begin_request(s,NULL)==MC_HTTP_INVALID_ARGUMENT);
    op=mc_http_begin_request(s,&r);assert(op>0);
    r.url[8]='X';r.headers[2]='z';r.body[0]='z';
    assert(mc_http_next_request(s,&out,legacy_url,sizeof(legacy_url),&n,&limit)==MC_HTTP_INVALID_ARGUMENT);
    assert(out==0);
    assert(mc_http_poll_response(s,op,&state,&error,&result,1)==0 && state==MC_HTTP_PENDING);
    assert(mc_http_next_request_v2(s,&out,&received)==1 && out==op);
    assert(received.method==MC_HTTP_POST && received.body_length==3 && memcmp(received.body,"a\0b",3)==0);
    assert(memcmp(received.headers,"{\"x\":\"y\"}",9)==0 && memcmp(received.url,URL,sizeof(URL)-1)==0);
    assert(received.max_response==8 && received.connect_timeout_ms==1 && received.read_timeout_ms==120000);
    assert(received.body[3]==0 && received.headers[9]==0);
    response.status=201;response.headers_length=15;memcpy(response.headers,"{\"x\":[\"a\",\"b\"]}",15);
    response.body_length=3;memcpy(response.body,"c\0d",3);
    assert(mc_http_complete_response(s,op,&response)==1);
    response.body[0]='z';response.headers[2]='z';
    assert(mc_http_complete_response(s,op,&response)==0);
    assert(mc_http_cancel(s,op)==0);
    assert(mc_http_poll_response(s,op,&state,&error,&result,0)==1 && state==MC_HTTP_RESPONSE && error==0);
    assert(result.status==201 && result.headers_length==15 && memcmp(result.headers,"{\"x\":[\"a\",\"b\"]}",15)==0);
    assert(result.body_length==3 && memcmp(result.body,"c\0d",3)==0 && result.body[3]==0);
    assert(mc_http_poll_response(s,op,&state,&error,&result,1)==1);
    assert(mc_http_poll_response(s,op,&state,&error,&result,0)==MC_HTTP_NOT_FOUND);
    r=received;
    for(int method=1;method<=4;method++) {
        r.method=method;r.body_length=(method==MC_HTTP_POST || method==MC_HTTP_PUT)?65536:0;
        r.headers_length=16384;op=mc_http_begin_request(s,&r);assert(op>0);
        assert(mc_http_next_request_v2(s,&out,&received)==1 && out==op && received.body_length==r.body_length);
        response.status=200;response.headers_length=16384;response.body_length=9;
        assert(mc_http_complete_response(s,op,&response)==1);
        assert(mc_http_poll_response(s,op,&state,&error,&result,1)==1 && state==MC_HTTP_FAILURE && error==MC_HTTP_ERROR_TOO_LARGE);
        assert(result.body_length==0 && result.headers_length==0);
    }
    r.method=MC_HTTP_GET;r.body_length=1;assert(mc_http_begin_request(s,&r)==MC_HTTP_INVALID_ARGUMENT);
    r.method=MC_HTTP_DELETE;assert(mc_http_begin_request(s,&r)==MC_HTTP_INVALID_ARGUMENT);
    r.body_length=0;r.method=5;assert(mc_http_begin_request(s,&r)==MC_HTTP_INVALID_ARGUMENT);r.method=1;
    r.headers_length=16385;assert(mc_http_begin_request(s,&r)==MC_HTTP_INVALID_ARGUMENT);r.headers_length=0;
    r.body_length=-1;assert(mc_http_begin_request(s,&r)==MC_HTTP_INVALID_ARGUMENT);r.body_length=0;
    r.connect_timeout_ms=0;assert(mc_http_begin_request(s,&r)==MC_HTTP_INVALID_ARGUMENT);r.connect_timeout_ms=1;
    r.read_timeout_ms=120001;assert(mc_http_begin_request(s,&r)==MC_HTTP_INVALID_ARGUMENT);r.read_timeout_ms=1;
    r.call_timeout_ms=120001;assert(mc_http_begin_request(s,&r)==MC_HTTP_INVALID_ARGUMENT);r.call_timeout_ms=1;
    r.url_length=8;memcpy(r.url,"http://a",8);
    assert(mc_http_begin_request(s,&r)==MC_HTTP_INVALID_ARGUMENT);r.allow_insecure=2;
    assert(mc_http_begin_request(s,&r)==MC_HTTP_INVALID_ARGUMENT);r.allow_insecure=1;
    op=mc_http_begin_request(s,&r);assert(op>0);
    assert(mc_http_complete_response(s,op,&response)==MC_HTTP_INVALID_ARGUMENT);
    assert(mc_http_next_request_v2(s,&out,&received)==1);
    response.headers_length=16385;assert(mc_http_complete_response(s,op,&response)==MC_HTTP_INVALID_ARGUMENT);
    response.headers_length=0;response.body_length=65537;assert(mc_http_complete_response(s,op,&response)==MC_HTTP_INVALID_ARGUMENT);
    assert(mc_http_cancel(s,op)==1);response.body_length=0;
    assert(mc_http_complete_response(s,op,&response)==0);
    assert(mc_http_poll_response(s,op,&state,&error,&result,1)==1 && state==MC_HTTP_CANCELLED);
    assert(mc_http_close(s)==0);
    assert(mc_http_next_request_v2(s,&out,&received)==MC_HTTP_NOT_FOUND && out==0);
}
int main(void) {
    test_v2();
    int32_t ids[4];for(int i=0;i<4;i++){ids[i]=mc_http_open();assert(ids[i]>0);}
    assert(mc_http_open()==MC_HTTP_CAPACITY);
    int32_t s=ids[0],ops[8];
    assert(mc_http_begin(s,NULL,1,1)==MC_HTTP_INVALID_ARGUMENT);
    const char *bad[]={"", "ftp://host", "http://", "http:///path", "https://user@host", "https://host/#x", "https://host/\\x", "https://host/a b"};
    for(size_t i=0;i<sizeof(bad)/sizeof(*bad);i++)assert(mc_http_begin(s,(const uint8_t*)bad[i],(int32_t)strlen(bad[i]),1)==MC_HTTP_INVALID_ARGUMENT);
    uint8_t embedded[]={'h','t','t','p',':','/','/','a',0,'b'};
    assert(mc_http_begin(s,embedded,sizeof(embedded),1)==MC_HTTP_INVALID_ARGUMENT);
    assert(begin(s,0)==MC_HTTP_INVALID_ARGUMENT && begin(s,65537)==MC_HTTP_INVALID_ARGUMENT);
    for(int i=0;i<8;i++){ops[i]=begin(s,8);assert(ops[i]>0);}
    assert(begin(s,8)==MC_HTTP_CAPACITY);
    int32_t out,n,state,status,error,limit;uint8_t body[16];
    assert(mc_http_next_request(s,&out,NULL,0,&n,&limit)==MC_HTTP_BUFFER_TOO_SMALL && out==0 && n==(int32_t)sizeof(URL)-1);
    assert(mc_http_complete(s,ops[0],200,NULL,0)==MC_HTTP_INVALID_ARGUMENT);
    dispatch(s,ops[0]);
    assert(mc_http_poll(s,ops[0],&state,&status,&error,NULL,0,&n,1)==0 && state==MC_HTTP_PENDING);
    uint8_t input[]={1,0,3};
    assert(mc_http_complete(s,ops[0],400,input,3)==1);input[0]=9;
    assert(mc_http_complete(s,ops[0],200,NULL,0)==0 && mc_http_cancel(s,ops[0])==0);
    assert(mc_http_poll(s,ops[0],&state,&status,&error,body,2,&n,1)==MC_HTTP_BUFFER_TOO_SMALL);
    assert(state==MC_HTTP_RESPONSE && status==400 && n==3);
    assert(mc_http_poll(s,ops[0],&state,&status,&error,body,sizeof(body),&n,0)==1 && body[0]==1 && body[1]==0);
    body[0]=99;assert(mc_http_poll(s,ops[0],&state,&status,&error,body,sizeof(body),&n,1)==1 && body[0]==1);
    assert(mc_http_state(s,ops[0])==MC_HTTP_NOT_FOUND && mc_http_complete(s,ops[0],200,NULL,0)==MC_HTTP_NOT_FOUND);
    int32_t newer=begin(s,8);assert(newer>ops[7]);dispatch(s,ops[1]); // recycled slot does not break FIFO
    assert(mc_http_cancel(s,ops[1])==1 && mc_http_cancel(s,ops[1])==0);
    assert(mc_http_complete(s,ops[1],200,NULL,0)==0);
    assert(read_result(s,ops[1],MC_HTTP_CANCELLED,0)==0);
    assert(read_result(s,ops[1],MC_HTTP_CANCELLED,1)==0);
    assert(mc_http_fail(s,ops[2],MC_HTTP_ERROR_TIMEOUT)==1);
    assert(read_result(s,ops[2],MC_HTTP_FAILURE,1)==MC_HTTP_ERROR_TIMEOUT);
    dispatch(s,ops[3]);uint8_t oversized[9]={0};
    assert(mc_http_complete(s,ops[3],200,oversized,9)==1);
    assert(read_result(s,ops[3],MC_HTTP_FAILURE,1)==MC_HTTP_ERROR_TOO_LARGE);
    assert(mc_http_fail(s,ops[4],99)==MC_HTTP_INVALID_ARGUMENT);
    assert(mc_http_state(ids[1],ops[4])==MC_HTTP_NOT_FOUND);
    assert(mc_http_close(s)==0 && mc_http_close(s)==MC_HTTP_NOT_FOUND);
    assert(mc_http_cancel(s,ops[4])==MC_HTTP_NOT_FOUND);
    int32_t reopened=mc_http_open();assert(reopened>s);
    for(int i=1;i<4;i++)assert(mc_http_close(ids[i])==0);
    s=reopened;
    uint8_t maxurl[2049];memset(maxurl,'x',sizeof(maxurl));memcpy(maxurl,"https://host/",13);
    assert(mc_http_begin(s,maxurl,2049,65536)==MC_HTTP_INVALID_ARGUMENT);
    int32_t maxop=mc_http_begin(s,maxurl,2048,65536);assert(maxop>0);
    maxurl[13]='z';uint8_t urlcopy[2048];
    assert(mc_http_next_request(s,&out,urlcopy,sizeof(urlcopy),&n,&limit)==1 && urlcopy[13]=='x' && limit==65536);
    static uint8_t maxbody[65536];memset(maxbody,42,sizeof(maxbody));
    assert(mc_http_complete(s,maxop,99,maxbody,sizeof(maxbody))==MC_HTTP_INVALID_ARGUMENT);
    assert(mc_http_complete(s,maxop,200,NULL,1)==MC_HTTP_INVALID_ARGUMENT);
    assert(mc_http_complete(s,maxop,200,maxbody,sizeof(maxbody))==1);
    assert(read_result(s,maxop,MC_HTTP_RESPONSE,1)==0);
    assert(mc_http_next_request(s,&out,urlcopy,sizeof(urlcopy),&n,&limit)==0);
    for(int i=0;i<100;i++) {
        int32_t op=begin(s,8);dispatch(s,op);int32_t args[]={s,op,-99,-99};pthread_t a,b;
        assert(pthread_create(&a,NULL,race_complete,args)==0);assert(pthread_create(&b,NULL,race_cancel,args)==0);
        assert(pthread_join(a,NULL)==0 && pthread_join(b,NULL)==0);
        assert(args[2]+args[3]==1);int32_t terminal_state=mc_http_state(s,op);
        assert(terminal_state==MC_HTTP_RESPONSE || terminal_state==MC_HTTP_CANCELLED);
        read_result(s,op,terminal_state,1);
    }
    /* Three-way close/complete/consuming-poll race: close may win before either,
     * complete may publish before close, and poll may see Pending or take the
     * result. No legal ordering can copy freed memory or mutate a reopened ID. */
    for(int i=0;i<100;i++) {
        int32_t raced_session=mc_http_open();assert(raced_session>0);
        int32_t raced_op=begin(raced_session,8);dispatch(raced_session,raced_op);
        close_race r={0};r.session=raced_session;r.op=raced_op;
        assert(pthread_mutex_init(&r.gate,NULL)==0);assert(pthread_cond_init(&r.ready,NULL)==0);
        pthread_t closer,completer,poller;
        assert(pthread_create(&closer,NULL,close_racer,&r)==0);
        assert(pthread_create(&completer,NULL,complete_racer,&r)==0);
        assert(pthread_create(&poller,NULL,poll_racer,&r)==0);
        assert(pthread_join(closer,NULL)==0);assert(pthread_join(completer,NULL)==0);
        assert(pthread_join(poller,NULL)==0);
        assert(pthread_cond_destroy(&r.ready)==0);assert(pthread_mutex_destroy(&r.gate)==0);
        assert(r.close_result==0);
        assert(r.complete_result==1 || r.complete_result==MC_HTTP_NOT_FOUND);
        assert(r.poll_result==0 || r.poll_result==1 || r.poll_result==MC_HTTP_NOT_FOUND);
        if(r.poll_result==0)assert(r.state==MC_HTTP_PENDING && r.length==0);
        if(r.poll_result==1) {
            assert(r.complete_result==1 && r.state==MC_HTTP_RESPONSE && r.status==201 &&
                   r.error==0 && r.length==4 && memcmp(r.body,"race",4)==0);
        }
        assert(mc_http_state(raced_session,raced_op)==MC_HTTP_NOT_FOUND);
        int32_t fresh_session=mc_http_open();assert(fresh_session>raced_session);
        int32_t fresh_op=begin(fresh_session,8);assert(fresh_op>raced_op);
        assert(mc_http_complete(raced_session,raced_op,200,NULL,0)==MC_HTTP_NOT_FOUND);
        assert(mc_http_complete(fresh_session,raced_op,200,NULL,0)==MC_HTTP_NOT_FOUND);
        assert(mc_http_complete(raced_session,fresh_op,200,NULL,0)==MC_HTTP_NOT_FOUND);
        assert(mc_http_cancel(fresh_session,raced_op)==MC_HTTP_NOT_FOUND);
        assert(mc_http_close(raced_session)==MC_HTTP_NOT_FOUND);
        assert(mc_http_state(fresh_session,fresh_op)==MC_HTTP_PENDING);
        dispatch(fresh_session,fresh_op);
        assert(mc_http_complete(fresh_session,fresh_op,200,NULL,0)==1);
        assert(read_result(fresh_session,fresh_op,MC_HTTP_RESPONSE,1)==0);
        assert(mc_http_close(fresh_session)==0);
    }
    /* Test exhaustion without any API to reset/reuse identifiers. */
    next_operation=INT32_MAX;int32_t last=begin(s,8);assert(last==INT32_MAX);
    assert(begin(s,8)==MC_HTTP_ID_EXHAUSTED);assert(mc_http_cancel(s,last)==1);
    read_result(s,last,MC_HTTP_CANCELLED,1);assert(begin(s,8)==MC_HTTP_ID_EXHAUSTED);
    assert(mc_http_close(s)==0);next_session=INT32_MAX;
    s=mc_http_open();assert(s==INT32_MAX);assert(mc_http_open()==MC_HTTP_ID_EXHAUSTED);
    assert(mc_http_close(s)==0 && mc_http_open()==MC_HTTP_ID_EXHAUSTED);
    puts("Copied HTTP C mailbox tests passed; no platform requests, Kotlin references or drain evidence");
}
