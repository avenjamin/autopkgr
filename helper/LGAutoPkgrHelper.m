//
//  LGAutoPkgrHelper.m
//  AutoPkgr
//
//  Created by Eldon on 7/28/14.
//  Copyright (c) 2014 The Linde Group, Inc. All rights reserved.
//

#import "LGAutoPkgrHelper.h"
#import "LGAutoPkgrProtocol.h"
#import "LGAutoPkgr.h"
#import <AHLaunchCtl/AHLaunchCtl.h>
#import "AHKeychain.h"

#import <pwd.h>
#import <syslog.h>

static const NSTimeInterval kHelperCheckInterval = 1.0; // how often to check whether to quit

@interface LGAutoPkgrHelper () <HelperAgent, NSXPCListenerDelegate>
@property (atomic, strong, readwrite) NSXPCListener *listener;
@property (weak) NSXPCConnection *connection;
@property (nonatomic, assign) BOOL helperToolShouldQuit;
@end

@implementation LGAutoPkgrHelper

- (id)init
{
    self = [super init];
    if (self) {
        self->_listener = [[NSXPCListener alloc] initWithMachServiceName:kLGAutoPkgrHelperToolName];
        self->_listener.delegate = self;
    }
    return self;
}

- (void)run
{
    [self.listener resume];
    while (!self.helperToolShouldQuit) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:kHelperCheckInterval]];
    }
}

#pragma mark - AutoPkgr Protocol
- (void)scheduleRun:(NSInteger)timer
               user:(NSString*)user
            program:(NSString*)program
      authorization:(NSData*)authData
              reply:(void (^)(NSError* error))reply
{
    
    NSError* error = [LGAutoPkgrAuthorizer checkAuthorization:authData
                                                      command:_cmd];
    if (!error) {
        AHLaunchJob* job = [AHLaunchJob new];
        job.Program = program;
        job.Label = kLGAutoPkgrLaunchDaemonPlist;
        job.ProgramArguments = @[ program, @"-runInBackground", @"YES", @"-asUser", user ];
        job.StartInterval = timer;
        job.SessionCreate = YES;
        
        [[AHLaunchCtl sharedControler] add:job toDomain:kAHGlobalLaunchDaemon error:&error];
    }
    
    reply(error);
}

- (void)removeScheduleWithAuthorization:(NSData*)authData reply:(void (^)(NSError*))reply
{
    NSError* error = [LGAutoPkgrAuthorizer checkAuthorization:authData
                                                      command:_cmd];
    if (!error) {
        [[AHLaunchCtl sharedControler] remove:kLGAutoPkgrLaunchDaemonPlist fromDomain:kAHGlobalLaunchDaemon error:&error];
    }
    
    reply(error);
}


#pragma mark - Update Password
- (void)addPassword:(NSString*)password forUser:(NSString*)user andAutoPkgr:(NSString*)autoPkgrLaunchPath reply:(void (^)(NSError*))reply
{
    NSError* error;
    
    AHKeychain* keychain = [AHKeychain systemKeychain];
    AHKeychainItem* item = [[AHKeychainItem alloc] init];
    item.label = kLGApplicationName;
    item.service = kLGApplicationName;
    item.account = user;
    item.password = password;
    item.trustedApplications = @[ autoPkgrLaunchPath ];
    [keychain saveItem:item error:&error];

    reply(error);
}

- (void)removePassword:(NSString*)password
               forUser:(NSString*)user
                 reply:(void (^)(NSError*))reply
{
    NSError* error;
    AHKeychain* keychain = [AHKeychain systemKeychain];
    AHKeychainItem* item = [[AHKeychainItem alloc] init];
    item.label = kLGApplicationName;
    item.service = kLGApplicationName;
    item.account = user;
    
    [keychain deleteItem:item error:&error];
    reply(error);
}

- (void)quitHelper:(void (^)(BOOL success))reply
{
    // this will cause the run-loop to exit;
    // you should call it via NSXPCConnection
    // during the applicationShouldTerminate routine
    self.helperToolShouldQuit = YES;
    reply(YES);
}

- (void)installPackageFromPath:(NSString*)path
                 authorization:(NSData*)authData
                         reply:(void (^)(NSError* error))reply;
{
    NSError* error;
    
    error = [LGAutoPkgrAuthorizer checkAuthorization:authData command:_cmd];
    if (error != nil) {
        reply(error);
        return;
    }
    
    NSTask* task = [NSTask new];
    task.launchPath = @"/usr/sbin/installer";
    task.arguments = @[ @"-pkg", path, @"-target", @"/" ];
    task.standardError = [NSPipe pipe];
    
    [task launch];
    [task waitUntilExit];
    
    error = [LGError errorWithTaskError:task verb:kLGAutoPkgUndefinedVerb];
    
    reply(error);
}

- (void)uninstall:(void (^)(NSError*))reply
{
   
    NSError *error;
    if(jobIsRunning(kLGAutoPkgrLaunchDaemonPlist, kAHGlobalLaunchDaemon))
    {
        [[AHLaunchCtl sharedControler] remove:kLGAutoPkgrLaunchDaemonPlist
                                   fromDomain:kAHGlobalLaunchDaemon
                                        error:&error];
    }
    
    [AHLaunchCtl removeFilesForHelperWithLabel:kLGAutoPkgrHelperToolName error:&error];

    reply(error);
}

//----------------------------------------
// Set up the one method of NSXPClistener
//----------------------------------------
- (BOOL)listener:(NSXPCListener*)listener shouldAcceptNewConnection:(NSXPCConnection*)newConnection
{
    
    newConnection.exportedObject = self;
    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(HelperAgent)];
    self.connection = newConnection;
    
    [newConnection resume];
    return YES;
}
@end