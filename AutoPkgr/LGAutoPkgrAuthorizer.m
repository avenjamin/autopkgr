#import "LGAutoPkgrAuthorizer.h"
#import "LGAutoPkgrProtocol.h"
#import "LGError.h"

@implementation LGAutoPkgrAuthorizer

static NSString *kCommandKeyAuthRightName = @"authRightName";
static NSString *kCommandKeyAuthRightDefault = @"authRightDefault";
static NSString *kCommandKeyAuthRightDesc = @"authRightDescription";

+ (NSDictionary *)commandInfo
{
    static dispatch_once_t dOnceToken;
    static NSDictionary *dCommandInfo;

    dispatch_once(&dOnceToken, ^{
        dCommandInfo = @{
            NSStringFromSelector(@selector(installPackageFromPath:authorization:reply:)) : @{
                kCommandKeyAuthRightName    : @"com.lindegroup.autopkgr.pkg.installer",
                kCommandKeyAuthRightDefault : @kAuthorizationRuleAuthenticateAsAdmin, 
                kCommandKeyAuthRightDesc    : NSLocalizedString(
                                                                @"AutoPkgr needs to run a package installer.  ",
                                                                @"prompt shown when user is required to authorize to insatll a package"
                                                                )
                },
            NSStringFromSelector(@selector(scheduleRun:user:program:authorization:reply:)) : @{
                kCommandKeyAuthRightName    : @"com.lindegroup.autopkgr.add.scheduled.run",
                kCommandKeyAuthRightDefault : @kAuthorizationRuleAuthenticateAsAdmin,
                kCommandKeyAuthRightDesc    : NSLocalizedString(
                                                                @"AutoPkgr is trying to add an autopkg run schedule.  ",
                                                                @"Prompt shown when user is required to authorize adding schedule"
                                                                )
                },
            NSStringFromSelector(@selector(removeScheduleWithAuthorization:reply:)) : @{
                kCommandKeyAuthRightName    : @"com.lindegroup.autopkgr.remove.schedule.run",
                kCommandKeyAuthRightDefault : @kAuthorizationRuleAuthenticateAsAdmin,
                kCommandKeyAuthRightDesc    : NSLocalizedString(
                                                                @"AutoPkgr is trying to remove the autopkg run schedule.  ",
                                                                @"Prompt shown when user is required to authorize removing schedule"
                                                                )
                },
            NSStringFromSelector(@selector(uninstall:reply:)) : @{
                    kCommandKeyAuthRightName    : @"com.lindegroup.autopkgr.uninstall.helper.tool",
                    kCommandKeyAuthRightDefault : @kAuthorizationRuleAuthenticateAsAdmin,
                    kCommandKeyAuthRightDesc    : NSLocalizedString(
                                                                    @"AutoPkgr wants to remove the helper tool and associated files.  ",
                                                                    @"Prompt shown when user is required to authorize removing schedule"
                                                                    )
                    },
        };
    });
    return dCommandInfo;
}

+ (NSString *)authorizationRightForCommand:(SEL)command
{
    return [self commandInfo][NSStringFromSelector(command)][kCommandKeyAuthRightName];
}

+ (void)enumerateRightsUsingBlock:(void (^)(NSString *authRightName, id authRightDefault, NSString *authRightDesc))block
{
    [self.commandInfo enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
#pragma unused(key)
#pragma unused(stop)
        NSDictionary *commandDict;
        NSString     *authRightName;
        id           authRightDefault;
        NSString     *authRightDesc;

        
        commandDict = (NSDictionary *) obj;
        assert([commandDict isKindOfClass:[NSDictionary class]]);

        authRightName = [commandDict objectForKey:kCommandKeyAuthRightName];
        assert([authRightName isKindOfClass:[NSString class]]);

        authRightDefault = [commandDict objectForKey:kCommandKeyAuthRightDefault];
        assert(authRightDefault != nil);

        authRightDesc = [commandDict objectForKey:kCommandKeyAuthRightDesc];
        assert([authRightDesc isKindOfClass:[NSString class]]);

        block(authRightName, authRightDefault, authRightDesc);
    }];
}

+ (void)setupAuthorizationRights:(AuthorizationRef)authRef
{
    assert(authRef != NULL);
    [[self class] enumerateRightsUsingBlock:^(NSString *authRightName, id authRightDefault, NSString *authRightDesc) {
        OSStatus    blockErr;
        blockErr = AuthorizationRightGet([authRightName UTF8String], NULL);
        if (blockErr == errAuthorizationDenied) {
            blockErr = AuthorizationRightSet(
                authRef,                                    // authRef
                [authRightName UTF8String],                 // rightName
                (__bridge CFTypeRef) authRightDefault,      // rightDefinition
                (__bridge CFStringRef) authRightDesc,       // descriptionKey
                NULL,                                       // bundle (NULL implies main bundle)
                CFSTR("Common")                             // localeTableName
            );
            assert(blockErr == errAuthorizationSuccess);
        } else { 
        }
    }];
}

#pragma mark - Authorization
+ (NSError *)checkAuthorization:(NSData *)authData command:(SEL)command
{
#pragma unused(authData)
    NSError *error;
    OSStatus err;
    OSStatus junk;
    AuthorizationRef authRef;

    assert(command != nil);

    authRef = NULL;

    error = nil;
    if ((authData == nil) || ([authData length] != sizeof(AuthorizationExternalForm))) {
        error = [NSError errorWithDomain:NSOSStatusErrorDomain code:paramErr userInfo:nil];
    }

    if (error == nil) {
        err = AuthorizationCreateFromExternalForm([authData bytes], &authRef);

        if (err == errAuthorizationSuccess) {
            AuthorizationItem oneRight = { NULL, 0, NULL, 0 };
            AuthorizationRights rights = { 1, &oneRight };

            oneRight.name = [[[self class] authorizationRightForCommand:command] UTF8String];
            assert(oneRight.name != NULL);

            err = AuthorizationCopyRights(
                authRef,
                &rights,
                NULL,
                kAuthorizationFlagExtendRights | kAuthorizationFlagInteractionAllowed,
                NULL);
        }
        if (err != errAuthorizationSuccess) {
            error = [LGError errorWithCode:kLGErrorAuthChallenge];
        }
    }

    if (authRef != NULL) {
        junk = AuthorizationFree(authRef, 0);
        assert(junk == errAuthorizationSuccess);
    }

    return error;
}

+ (NSData *)authorizeHelper
{
    OSStatus err;
    AuthorizationExternalForm extForm;
    AuthorizationRef authRef;
    NSData *authorization;

    err = AuthorizationCreate(NULL, NULL, 0, &authRef);
    if (err == errAuthorizationSuccess) {
        err = AuthorizationMakeExternalForm(authRef, &extForm);
    }
    if (err == errAuthorizationSuccess) {
        authorization = [[NSData alloc] initWithBytes:&extForm length:sizeof(extForm)];
    }
    assert(err == errAuthorizationSuccess);

    if (authRef) {
        [[self class] setupAuthorizationRights:authRef];
    }
    return authorization;
}

@end
