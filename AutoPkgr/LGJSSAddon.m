//
//  LGJSSAddon.m
//  AutoPkgr
//
//  Created by Eldon on 9/25/14.
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

#import "LGJSSAddon.h"
#import "LGAutopkgr.h"
#import "LGHTTPRequest.h"
#import "LGTestPort.h"
#import "LGInstaller.h"
#import "LGHostInfo.h"
#import "LGAutoPkgTask.h"

#pragma mark - Class constants
NSString *defaultJSSRepo = @"https://github.com/sheagcraig/jss-recipes.git";

@implementation LGJSSAddon {
    LGDefaults *_defaults;
    LGTestPort *_portTester;
    BOOL _serverReachable;
    BOOL _installRequestedDuringConnect;
}

- (void)awakeFromNib
{
    _defaults = [LGDefaults standardUserDefaults];
    _installRequestedDuringConnect = NO;

    [self showInstallTabItems:NO];

    [_jssInstallStatusLight setImage:[NSImage LGStatusNotInstalled]];
    if ([LGHostInfo jssAddonInstalled] && _defaults.JSSRepos) {
        [self showInstallTabItems:YES];
    } else {
        [_jssInstallButton setEnabled:YES];
        [_jssInstallStatusTF setStringValue:@"JSS AutoPkg Addon not installed."];
    }

    _jssAPIUsernameTF.safeStringValue = _defaults.JSSAPIUsername;
    _jssAPIPasswordTF.safeStringValue = _defaults.JSSAPIPassword;

    if (_defaults.JSSURL) {
        _jssURLTF.safeStringValue = _defaults.JSSURL;
    }

    [self updateJSSURL:nil];
    [_jssDistributionPointTableView reloadData];
}

#pragma mark - IBActions
- (IBAction)updateJSSUsername:(id)sender
{
    [self evaluateRepoViability];
}

- (IBAction)updateJSSPassword:(id)sender
{
    [self evaluateRepoViability];
}

- (IBAction)updateJSSURL:(id)sender
{
    [self evaluateRepoViability];
    [self checkReachability];

    [_jssReloadServerBT setEnabled:_jssURLTF.safeStringValue ? YES : NO];
}

- (IBAction)reloadJSSServerInformation:(id)sender
{
    if (!_jssURLTF.safeStringValue) {
        return;
    }

    if (![LGHostInfo jssAddonInstalled]) {
        _installRequestedDuringConnect = YES;
        if ([self requiresInstall]) {
            return;
        }
    }

    [self startStatusUpdate];
    LGHTTPRequest *request = [[LGHTTPRequest alloc] init];
    [request retrieveDistributionPoints:_jssURLTF.stringValue
                               withUser:_jssAPIUsernameTF.stringValue
                            andPassword:_jssAPIPasswordTF.stringValue
                                  reply:^(NSDictionary *distributionPoints, NSError *error) {
                                      [self stopStatusUpdate:error];
                                      [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                                           id distPoints = distributionPoints[@"distribution_point"];
                                           if (distPoints) {
                                               NSArray *cleanedArray = [self evaluateJSSRepoDictionaries:distPoints];
                                               if (cleanedArray) {
                                                   _defaults.JSSRepos = cleanedArray;
                                                   [self saveDefaults];
                                                   [_jssStatusLight setImage:[NSImage LGStatusAvaliable]];
                                                   [_jssDistributionPointTableView reloadData];
                                               }
                                               
                                           }
                                      }];
                                  }];
}

- (IBAction)installJSSAddon:(id)sender
{
    LGInstaller *installer = [[LGInstaller alloc] init];
    installer.progressDelegate = [NSApp delegate];
    [_jssInstallButton setEnabled:NO];
    [installer installJSSAddon:^(NSError *error) {
        BOOL success = (error == nil);
        if (success) {
            NSString *message = [NSString stringWithFormat:@"Adding %@",defaultJSSRepo];
            [[NSApp delegate] startProgressWithMessage:message];
            [LGAutoPkgTask repoAdd:defaultJSSRepo reply:^(NSError *error) {
                [[NSApp delegate]stopProgress:error];
                [[NSNotificationCenter defaultCenter] postNotificationName:kLGNotificationReposModified
                                                                    object:nil];

                if (_installRequestedDuringConnect) {
                    _installRequestedDuringConnect = NO;
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        [self reloadJSSServerInformation:self];
                    }];
                }
            }];
        }
        [[NSOperationQueue mainQueue]addOperationWithBlock:^{
            if (success) {
                [self showInstallTabItems:YES];
            }
        }];
    }];
}

#pragma mark - Progress
- (void)startStatusUpdate
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [_jssStatusLight setHidden:YES];
        [_jssStatusSpinner setHidden:NO];
        [_jssStatusSpinner startAnimation:self];
    }];
}

- (void)stopStatusUpdate:(NSError *)error
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [_jssStatusLight setHidden:NO];
        [_jssStatusSpinner setHidden:YES];
        [_jssStatusSpinner stopAnimation:self];
        if (error) {
            [[NSApp delegate] stopProgress:error];
            [_jssStatusLight setImage:[NSImage LGStatusUnavaliable]];
        }
    }];
}

#pragma mark - NSTableViewDataSource
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return [_defaults.JSSRepos count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    NSDictionary *distributionPoint;
    if ([_defaults.JSSRepos count] >= row) {
        distributionPoint = _defaults.JSSRepos[row];
    };
    NSString *identifier = [tableColumn identifier];
    return distributionPoint[identifier];
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    NSMutableArray *workingArray = [NSMutableArray arrayWithArray:_defaults.JSSRepos];
    NSMutableDictionary *distributionPoint = [NSMutableDictionary dictionaryWithDictionary:workingArray[row]];

    [distributionPoint setValue:object forKey:[tableColumn identifier]];
    [workingArray replaceObjectAtIndex:row withObject:distributionPoint];

    _defaults.JSSRepos = [NSArray arrayWithArray:workingArray];
}

#pragma mark - Utility
- (void)checkReachability
{
    if (!_jssURLTF.safeStringValue) {
        return;
    }
    // If there's a currently processing _portTester nil it out
    if (_portTester) {
        _portTester = nil;
    }

    _portTester = [[LGTestPort alloc] init];
    [self startStatusUpdate];

    [_portTester testServerURL:_jssURLTF.safeStringValue reply:^(BOOL reachable) {
        _serverReachable = reachable;
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if (reachable && [_defaults.JSSURL isEqualToString:_jssURLTF.safeStringValue]) {
                _jssStatusLight.image = [NSImage LGStatusAvaliable];
            } else if (reachable) {
                _jssStatusLight.image = [NSImage LGStatusPartiallyAvaliable];
            } else {
                _jssStatusLight.image = [NSImage LGStatusUnavaliable];
            }
            // No need to keep this around so nil it out.
            _portTester = nil;
        }];
        [self stopStatusUpdate:nil];
    }];
}

- (NSArray *)evaluateJSSRepoDictionaries:(id)distPoints
{
    NSArray *dictArray;
    NSMutableArray *newRepos;

    // If there is just one ditribution point distPoint will be a dictionary entry
    // and we need to normalize it here by wrapping it in an array.
    if ([distPoints isKindOfClass:[NSDictionary class]]) {
        dictArray = @[ distPoints ];
    }
    // If there are more then one entries distPoint will be an array, so pass it along.
    else if ([distPoints isKindOfClass:[NSArray class]]) {
        dictArray = distPoints;
    }

    if (dictArray) {
        newRepos = [[NSMutableArray alloc] init];
        for (NSDictionary *repo in dictArray) {
            if (!repo[@"password"]) {
                NSString *name = repo[@"name"];
                NSString *password = [self promptForSharePassword:name];
                if (password && ![password isEqualToString:@""]) {
                    [newRepos addObject:@{ @"name" : name,
                                           @"password" : password }];
                }
            } else {
                [newRepos addObject:repo];
            }
        }
    }

    return [NSArray arrayWithArray:newRepos];
}

- (void)evaluateRepoViability
{
    // if all settings have been removed clear out the JSS_REPOS key too
    if (!_jssAPIPasswordTF.safeStringValue && !_jssAPIUsernameTF.safeStringValue && !_jssURLTF.safeStringValue) {
        _defaults.JSSRepos = nil;
        [self saveDefaults];
        [self showInstallTabItems:NO];
        [_jssStatusLight setImage:[NSImage LGStatusNone]];
    } else if (![_defaults.JSSAPIPassword isEqualToString:_jssAPIPasswordTF.safeStringValue] || ![_defaults.JSSAPIUsername isEqualToString:_jssAPIUsernameTF.safeStringValue] || ![_defaults.JSSURL isEqualToString:_jssURLTF.safeStringValue]) {
        // Update server status
        if ([_jssStatusLight.image isEqualTo:[NSImage LGStatusAvaliable]]) {
            [_jssStatusLight setImage:[NSImage LGStatusPartiallyAvaliable]];
        }

        // Show installer status
        [self showInstallTabItems:YES];
    }

    [_jssDistributionPointTableView reloadData];
}

- (void)showInstallTabItems:(BOOL)show
{
    // Show installer status
    [_jssInstallStatusLight setHidden:!show];
    [_jssInstallStatusTF setHidden:!show];
    [_jssInstallButton setHidden:!show];
    if (show) {
        NSOperationQueue *bgQueue = [[NSOperationQueue alloc] init];
        [bgQueue addOperationWithBlock:^{
            BOOL updateAvaliable = [LGHostInfo jssAddonUpdateAvailable];
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [_jssInstallButton setEnabled:updateAvaliable];
                if (updateAvaliable) {
                    _jssInstallButton.title = @"Update JSS AutoPkg Addon";
                    _jssInstallStatusTF.stringValue = kLGJSSAutoPkgAddonUpdateAvailableLabel;
                    _jssInstallStatusLight.image = [NSImage LGStatusUpdateAvaliable];
                } else {
                    _jssInstallButton.title = @"Install JSS AutoPkg Addon";
                    _jssInstallStatusTF.stringValue = kLGJSSAutoPkgAddonInstalledLabel;
                    _jssInstallStatusLight.image = [NSImage LGStatusUpToDate];
                }
            }];
        }];
    }
}

- (void)saveDefaults
{
    _defaults.JSSAPIPassword = _jssAPIPasswordTF.safeStringValue;
    _defaults.JSSAPIUsername = _jssAPIUsernameTF.safeStringValue;
    _defaults.JSSURL = _jssURLTF.safeStringValue;
}

- (NSString *)promptForSharePassword:(NSString *)shareName
{
    NSString *password;
    NSString *alertString = [NSString stringWithFormat:@"Please enter read/write password for the %@ distribution point.", shareName];
    NSAlert *alert = [NSAlert alertWithMessageText:alertString
                                     defaultButton:@"OK"
                                   alternateButton:@"Cancel"
                                       otherButton:nil
                         informativeTextWithFormat:@""];

    NSSecureTextField *input = [[NSSecureTextField alloc] init];
    [input setFrame:NSMakeRect(0, 0, 300, 24)];
    [alert setAccessoryView:input];

    NSInteger button = [alert runModal];
    if (button == NSAlertDefaultReturn) {
        [input validateEditing];
        password = [input stringValue];
        if (!password || [password isEqualToString:@""]) {
            return [self promptForSharePassword:shareName];
        }
    }

    return password;
}

- (BOOL)requiresInstall
{
    BOOL required = NO;

    if (![LGHostInfo jssAddonInstalled]) {
        NSAlert *alert = [NSAlert alertWithMessageText:@"Install JSS AutoPkg Addon?"
                                         defaultButton:@"Install"
                                       alternateButton:@"Cancel"
                                           otherButton:nil
                             informativeTextWithFormat:@"The JSS AutoPkg Addon is not currently installed, would you like to install it now?"];

        NSInteger button = [alert runModal];
        if (button == NSAlertDefaultReturn) {
            [self installJSSAddon:nil];
        } else {
            _installRequestedDuringConnect = NO;
        }
        return YES;
    }
    return required;
}
@end
