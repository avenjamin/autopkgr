//
//  LGEmailer.m
//  AutoPkgr
//
//  Created by James Barclay on 6/26/14.
//
//  Copyright 2014 The Linde Group, Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "LGEmailer.h"
#import "LGAutoPkgr.h"
#import "LGHostInfo.h"
#import "AHKeychain.h"

@implementation LGEmailer

- (void)sendEmailNotification:(NSString *)subject message:(NSString *)message
{
    LGDefaults *defaults = [[LGDefaults alloc] init];
    
    if (defaults.sendEmailNotificationsWhenNewVersionsAreFoundEnabled) {
        BOOL TLS = defaults.SMTPTLSEnabled;
        
        MCOSMTPSession *smtpSession = [[MCOSMTPSession alloc] init];
        smtpSession.username = defaults.SMTPUsername ? defaults.SMTPUsername:@"";
        smtpSession.hostname = defaults.SMTPServer ? defaults.SMTPServer:@"";
        smtpSession.port = (int)defaults.SMTPPort;
        
        if (TLS) {
            DLog(@"SSL/TLS is enabled for %@.", defaults.SMTPServer);
            // If the SMTP port is 465, use MCOConnectionTypeTLS.
            // Otherwise use MCOConnectionTypeStartTLS.
            if (smtpSession.port == 465) {
                smtpSession.connectionType = MCOConnectionTypeTLS;
            } else {
                smtpSession.connectionType = MCOConnectionTypeStartTLS;
            }
        } else {
            DLog(@"SSL/TLS is _not_ enabled for %@.", defaults.SMTPServer);
            smtpSession.connectionType = MCOConnectionTypeClear;
        }
        
        // Retrieve the SMTP password from the default
        // keychain if it exists
        NSError *error = nil;
        
        if (smtpSession.username) {
            if (defaults.SMTPUsername) {
                NSString *password = [AHKeychain getPasswordForService:kLGApplicationName account:defaults.SMTPUsername keychain:kAHKeychainSystemKeychain error:&error];
                
            if (smtpSession.username != nil && ![smtpSession.username isEqual:@""] && password) {
                DLog(@"Retrieved password from keychain for account %@.", smtpSession.username);
                smtpSession.password = password ? password:@"";
            }
        }
        
        MCOMessageBuilder * builder = [[MCOMessageBuilder alloc] init];
        [[builder header] setFrom:[MCOAddress addressWithDisplayName:@"AutoPkgr Notification"
                                                             mailbox:defaults.SMTPFrom ? defaults.SMTPFrom:@""]];
        
        NSMutableArray *to = [[NSMutableArray alloc] init];
        for (NSString *toAddress in defaults.SMTPTo) {
            if (![toAddress isEqual:@""]) {
                MCOAddress *newAddress = [MCOAddress addressWithMailbox:toAddress];
                [to addObject:newAddress];
            }
        }
        NSString *fullSubject = [NSString stringWithFormat:@"%@ on %@",subject,[[NSHost currentHost] name]];
        [[builder header] setTo:to];
        [[builder header] setSubject:fullSubject];
        [builder setHTMLBody:message];
        NSData * rfc822Data = [builder data];
        
        MCOSMTPSendOperation *sendOperation = [smtpSession sendOperationWithData:rfc822Data];
        [sendOperation start:^(NSError *error) {
            NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:@{kLGNotificationUserInfoSubject:subject,
                                                                                            kLGNotificationUserInfoMessage:message}];
            
            if (error) {
                NSLog(@"Error sending email from %@: %@", smtpSession.username, error);
                [userInfo setObject:error forKey:kLGNotificationUserInfoError];
            } else {
                NSLog(@"Successfully sent email from %@.", smtpSession.username);
            }
            
            self.complete = YES;
            [center postNotificationName:kLGNotificationEmailSent
                                  object:self
                                userInfo:[NSDictionary dictionaryWithDictionary:userInfo]];
        }];
        }
    }
}

- (void)sendTestEmail
{
    // Send a test email notification when the user
    // clicks "Send Test Email"
    NSString *subject = @"Test notification from AutoPkgr";
    NSString *message = @"This is a test notification from <strong>AutoPkgr</strong>.";
    // Send the email
    [self sendEmailNotification:subject message:message];
}

- (void)sendEmailForReport:(NSDictionary *)report error:(NSError *)error
{
    // Get arrays of new downloads/packages from the plist
    NSMutableString *message;
    NSString *subject;
    NSArray *newDownloads;
    NSArray *newPackages;
    
    if (report) {
        newDownloads = [report objectForKey:@"new_downloads"];
        newPackages = [report objectForKey:@"new_packages"];
    }
    
    if ([newDownloads count]) {
        message = [[NSMutableString alloc] init];
        NSLog(@"New stuff was downloaded.");
        
        // Create the subject string
        subject = [NSString stringWithFormat:@"[%@] New software avaliable for testing",kLGApplicationName];
        
        // Append the the message string with report
        [message appendFormat:@"The following software is now available for testing:<br />"];
        
        for (NSString *path in newDownloads) {
            // Get just the application name from the path in the new_downloads dict
            NSString *app = [[path lastPathComponent] stringByDeletingPathExtension];
            
            // Write the app to the string
            [message appendFormat:@"<strong>%@</strong>: ",app];
            
            // The default version is not detected, override later
            NSString *version = @"Version not detected";
            for (NSDictionary *dct in newPackages) {
                NSString *pkgPath = [dct objectForKey:@"pkg_path"];
                if ([pkgPath rangeOfString:app options:NSCaseInsensitiveSearch].location != NSNotFound && dct[@"version"]) {
                    version = dct[@"version"];
                    break;
                }
            }
            [message appendFormat:@"%@<br/>",version];
        }
    } else {
        DLog(@"Nothing new was downloaded.");
    }
    
    if (error) {
        if(!message){
            message = [[NSMutableString alloc] init];
        }
        
        if (!subject){
            subject = [NSString stringWithFormat:@"[%@] Error occured while running AutoPkg",kLGApplicationName];
        }
        [message appendFormat:@"<br /><strong>The following error occured:</strong><br/>%@<br/>%@",error.localizedDescription,error.localizedRecoverySuggestion];
    }
    
    if (message) {
        [self sendEmailNotification:subject message:message];
    }else{
        self.complete = YES;
    }
}

@end
