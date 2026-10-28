#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>
#import "TouchBridge.h"
#import "VirtualGamepad.h"
#import "ControllerPage.generated.h"
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>
#include <errno.h>
#include <atomic>
#include <cmath>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include <algorithm>

// HTTP and RFC6455 WebSocket server inside Vice City. Trusted LAN ONLY.
namespace {
constexpr int PORT = 8765;
// Fixed-size, zero-initialized PIN storage. Unlike a global std::string,
// this is safe to write from a dylib constructor before C++ dynamic init.
char pin[7] = {};
std::atomic<bool> controllerConnected{false};

std::string localAddress() {
    struct ifaddrs *list = nullptr;
    if (getifaddrs(&list) != 0) return "iPad-IP";
    std::string ip = "iPad-IP";
    for (struct ifaddrs *it = list; it; it = it->ifa_next) {
        if (it->ifa_addr && it->ifa_addr->sa_family == AF_INET &&
            strcmp(it->ifa_name,"en0") == 0) {
            char buf[INET_ADDRSTRLEN] = {};
            if (inet_ntop(AF_INET, &((struct sockaddr_in *)it->ifa_addr)->sin_addr,
                          buf,sizeof(buf))) { ip = buf; break; }
        }
    }
    freeifaddrs(list);
    return ip;
}
void overlay(int attempt = 0) {
    UIApplication *app = UIApplication.sharedApplication;
    UIWindow *window = app.keyWindow;
    if (!window && app.windows.count) window = app.windows.firstObject;
    if (!window) {
        if (attempt < 30)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),
                dispatch_get_main_queue(), ^{overlay(attempt+1);});
        return;
    }
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(15,16,350,49)];
    label.tag = 584276;
    label.numberOfLines = 2;
    label.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightMedium];
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = .7;
    label.textColor = UIColor.whiteColor;
    label.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:.8];
    label.layer.cornerRadius = 8;
    label.layer.masksToBounds = YES;
    label.userInteractionEnabled = NO;
    label.text = [NSString stringWithFormat:@" VCRemote http://%s:%d\n PIN: %s",
        localAddress().c_str(), PORT, pin];
    [window addSubview:label];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC),
        dispatch_get_main_queue(), ^{[label removeFromSuperview];});
}

bool readN(int fd, void *dst, size_t size) {
    unsigned char *p = (unsigned char *)dst;
    while (size) {
        ssize_t n = recv(fd,p,size,0);
        if (n <= 0) return false;
        p += n; size -= (size_t)n;
    }
    return true;
}
bool sendString(int fd,const std::string &s) {
    size_t offset = 0;
    while (offset < s.size()) {
        ssize_t n = send(fd,s.data()+offset,s.size()-offset,0);
        if (n <= 0) return false;
        offset += (size_t)n;
    }
    return true;
}
bool readHeaders(int fd,std::string &s) {
    char c;
    while (s.size() < 8192) {
        if (!readN(fd,&c,1)) return false;
        s += c;
        if (s.size() >= 4 && s.compare(s.size()-4,4,"\r\n\r\n") == 0)
            return true;
    }
    return false;
}
std::string header(const std::string &input,const std::string &name) {
    std::string lowered = input;
    std::transform(lowered.begin(),lowered.end(),lowered.begin(),
        [](unsigned char c){return (char)tolower(c);});
    std::string lowerName = name;
    std::transform(lowerName.begin(),lowerName.end(),lowerName.begin(),
        [](unsigned char c){return (char)tolower(c);});
    size_t start = lowered.find("\r\n"+lowerName+":");
    if (start == std::string::npos) return "";
    start += lowerName.size()+3;
    size_t end = input.find("\r\n",start);
    std::string value = input.substr(start,end-start);
    size_t a = value.find_first_not_of(" \t");
    size_t b = value.find_last_not_of(" \t");
    return a == std::string::npos ? "" : value.substr(a,b-a+1);
}
void respond(int fd,const std::string &status,const std::string &mime,
             const std::string &body) {
    sendString(fd,"HTTP/1.1 "+status+"\r\nContent-Type: "+mime+
        "\r\nContent-Length: "+std::to_string(body.size())+
        "\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"+body);
}
std::string acceptToken(const std::string &key) {
    std::string s = key+"258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(s.data(),(CC_LONG)s.size(),digest);
    NSData *data = [NSData dataWithBytes:digest length:sizeof(digest)];
    return std::string([[data base64EncodedStringWithOptions:0] UTF8String]);
}
void wsReply(int fd,unsigned char opcode,const std::string &payload) {
    if (payload.size() > 125) return;
    std::string frame;
    frame += (char)(0x80 | opcode);
    frame += (char)payload.size();
    frame += payload;
    sendString(fd,frame);
}
void processMessage(const std::string &s) {
    if (s == "P") return; // keepalive
    if (s == "M,g") {
        dispatch_async(dispatch_get_main_queue(), ^{
            VCReleaseAllTouches();
            VCGamepadSetActive(YES);
        });
        return;
    }
    if (s == "M,t") {
        dispatch_async(dispatch_get_main_queue(), ^{
            VCGamepadSetActive(NO);
            VCReleaseAllTouches();
        });
        return;
    }
    if (s.size() > 100 || s.size() < 3 ||
        (s.compare(0,2,"T,") != 0 && s.compare(0,2,"G,") != 0)) return;
    bool gamepadEvent = (s[0] == 'G');
    int id = 0, consumed = 0;
    char phase = 0;
    double x = 0, y = 0;
    int parsed = sscanf(s.c_str()+2,"%d,%c,%lf,%lf%n",
                        &id,&phase,&x,&y,&consumed);
    if (parsed != 4 || (size_t)consumed != s.size()-2 ||
        id < 1 || id > 12 || (phase != 'b' && phase != 'm' && phase != 'e') ||
        !std::isfinite(x) || !std::isfinite(y) ||
        x < (gamepadEvent ? -1 : 0) || x > 1 ||
        y < (gamepadEvent ? -1 : 0) || y > 1) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gamepadEvent) VCGamepadInject(id,phase,x,y);
        else VCInjectTouch(id,phase,x,y);
    });
}

void client(int fd) {
    @autoreleasepool {
        int noSigPipe = 1;
        setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&noSigPipe,sizeof(noSigPipe));
        struct timeval timeout = {12,0};
        setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
        std::string request;
        if (!readHeaders(fd,request)) {close(fd);return;}
        size_t a = request.find(' '), b = request.find(' ',a+1);
        if (a == std::string::npos || b == std::string::npos ||
            request.substr(0,a) != "GET") {
            respond(fd,"405 Method Not Allowed","text/plain","GET only");
            close(fd);return;
        }
        std::string path = request.substr(a+1,b-a-1);
        if (path == "/" || path == "/index.html") {
            respond(fd,"200 OK","text/html; charset=utf-8",
                std::string(kControllerHTML,kControllerHTMLLength));
            close(fd);return;
        }
        std::string prefix="/ws?pin=";
        if (path.compare(0,prefix.size(),prefix) != 0 ||
            strlen(pin) != 6 ||
            path.substr(prefix.size()) != pin ||
            header(request,"Upgrade") != "websocket") {
            respond(fd,"403 Forbidden","text/plain","Wrong PIN or upgrade");
            close(fd);return;
        }
        if (controllerConnected.exchange(true)) {
            respond(fd,"409 Conflict","text/plain","Controller already connected");
            close(fd);return;
        }
        std::string key = header(request,"Sec-WebSocket-Key");
        if (key.size() < 16 || key.size() > 32) {
            controllerConnected = false;close(fd);return;
        }
        std::string response =
            "HTTP/1.1 101 Switching Protocols\r\n"
            "Upgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: "+
            acceptToken(key)+"\r\n\r\n";
        if (sendString(fd,response)) {
            while (true) {
                unsigned char first[2];
                if (!readN(fd,first,2)) break;
                size_t size = first[1] & 127;
                bool masked = (first[1] & 128) != 0;
                unsigned char opcode = first[0] & 15;
                if ((first[0] & 128) == 0 || !masked || size > 125) break;
                unsigned char mask[4];
                if (!readN(fd,mask,4)) break;
                std::string payload(size,'\0');
                if (size && !readN(fd,payload.data(),size)) break;
                for (size_t i=0;i<size;i++) payload[i] ^= mask[i%4];
                if (opcode == 8) break;
                if (opcode == 9) {wsReply(fd,10,payload);continue;}
                if (opcode != 1) break;
                processMessage(payload);
            }
        }
        shutdown(fd,SHUT_RDWR);close(fd);
        controllerConnected = false;
        dispatch_async(dispatch_get_main_queue(), ^{
            VCGamepadSetActive(NO);
            VCReleaseAllTouches();
        });
    }
}
void server() {
    @autoreleasepool {
        int fd = socket(AF_INET,SOCK_STREAM,0);
        if (fd < 0) {NSLog(@"[VCRemote] socket failed");return;}
        int yes = 1;
        setsockopt(fd,SOL_SOCKET,SO_REUSEADDR,&yes,sizeof(yes));
        struct sockaddr_in a = {};
        a.sin_family = AF_INET;
        a.sin_port = htons(PORT);
        a.sin_addr.s_addr = htonl(INADDR_ANY);
        if (bind(fd,(struct sockaddr *)&a,sizeof(a)) ||
            listen(fd,5)) {
            NSLog(@"[VCRemote] port %d unavailable (errno %d)",PORT,errno);
            close(fd);return;
        }
        NSLog(@"[VCRemote] available: http://%s:%d",localAddress().c_str(),PORT);
        for (;;) {
            int accepted = accept(fd,nullptr,nullptr);
            if (accepted < 0) {
                if (errno == EINTR) continue;
                break;
            }
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
                client(accepted);
            });
        }
        close(fd);
    }
}
} // namespace

__attribute__((constructor))
static void startVCRemote(void) {
    @autoreleasepool {
        char six[7] = {};
        snprintf(six,sizeof(six),"%06u",100000+arc4random_uniform(900000));
        memcpy(pin, six, sizeof(pin));
        dispatch_async(dispatch_get_main_queue(), ^{overlay();});
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{server();});
    }
}
