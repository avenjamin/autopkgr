//
//  LGAutoPkgRunner.m
//  AutoPkgr
//
//  Created by James Barclay on 7/1/14.
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

#import "LGAutoPkgRunner.h"
#import "LGApplications.h"
#import "LGEmailer.h"
#import "LGHostInfo.h"
#import "LGVersionComparator.h"
#import "LGConstants.h"

@implementation LGAutoPkgRunner

- (NSArray *)getLocalAutoPkgRecipes
{
    // Set up our task, pipe, and file handle
    NSTask *autoPkgRecipeListTask = [[NSTask alloc] init];
    NSPipe *autoPkgRecipeListPipe = [NSPipe pipe];
    NSFileHandle *fileHandle = [autoPkgRecipeListPipe fileHandleForReading];

    // Set up our launch path and args
    NSString *launchPath = @"/usr/bin/python";
    NSArray *args = [NSArray arrayWithObjects:@"/usr/local/bin/autopkg", @"list-recipes", nil];

    // Configure the task
    [autoPkgRecipeListTask setLaunchPath:launchPath];
    [autoPkgRecipeListTask setArguments:args];
    [autoPkgRecipeListTask setStandardOutput:autoPkgRecipeListPipe];

    // Launch the task
    [autoPkgRecipeListTask launch];
    [autoPkgRecipeListTask waitUntilExit];

    // Read our data from the fileHandle
    NSData *autoPkgRecipeListTaskData = [fileHandle readDataToEndOfFile];
    // Init our string with data from the fileHandle
    NSString *autoPkgRecipeListResults = [[NSString alloc] initWithData:autoPkgRecipeListTaskData encoding:NSUTF8StringEncoding];
    // Init our array with the string separated by newlines
    NSArray *autoPkgRecipeListArray = [autoPkgRecipeListResults componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];

    // Strip empty strings from our array
    NSMutableArray *arrayWithoutEmptyStrings = [[NSMutableArray alloc] init];
    for (NSString *recipe in autoPkgRecipeListArray) {
        if (![recipe isEqualToString:@""]) {
            [arrayWithoutEmptyStrings addObject:recipe];
        }
    }

    return arrayWithoutEmptyStrings;
}

- (NSArray *)getLocalAutoPkgRecipeRepos
{
    // Set up our task, pipe, and file handle
    NSTask *autoPkgRepoListTask = [[NSTask alloc] init];
    NSPipe *autoPkgRepoListPipe = [NSPipe pipe];
    NSFileHandle *fileHandle = [autoPkgRepoListPipe fileHandleForReading];

    // Set up our launch path and args
    NSString *launchPath = @"/usr/bin/python";
    NSArray *args = [NSArray arrayWithObjects:@"/usr/local/bin/autopkg", @"repo-list", nil];

    // Configure the task
    [autoPkgRepoListTask setLaunchPath:launchPath];
    [autoPkgRepoListTask setArguments:args];
    [autoPkgRepoListTask setStandardOutput:autoPkgRepoListPipe];

    // Launch the task
    [autoPkgRepoListTask launch];
    [autoPkgRepoListTask waitUntilExit];

    // Read our data from the fileHandle
    NSData *autoPkgRepoListTaskData = [fileHandle readDataToEndOfFile];
    // Init our string with data from the fileHandle
    NSString *autoPkgRepoListResults = [[NSString alloc] initWithData:autoPkgRepoListTaskData encoding:NSUTF8StringEncoding];
    // Init our array with the string separated by newlines
    NSArray *autoPkgRepoListArray = [autoPkgRepoListResults componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];

    // Strip empty strings from our array
    NSMutableArray *arrayWithoutEmptyStrings = [[NSMutableArray alloc] init];
    for (NSString *repo in autoPkgRepoListArray) {
        if (![repo isEqualToString:@""]) {
            [arrayWithoutEmptyStrings addObject:repo];
        }
    }

    return arrayWithoutEmptyStrings;
}

- (void)addAutoPkgRecipeRepo:(NSString *)repoURL
{
    NSString *addString = [NSString stringWithFormat:@"Adding %@", repoURL];
    [[NSNotificationCenter defaultCenter] postNotificationName:kProgressStartNotification
                                                        object:nil
                                                      userInfo:@{ kNotificationUserInfoMessage : addString }];
    // Set up task, pipe, and file handle
    NSTask *autoPkgRepoAddTask = [[NSTask alloc] init];
    NSPipe *autoPkgRepoAddPipe = [NSPipe pipe];

    // Set up launch path and args
    NSString *launchPath = @"/usr/bin/python";
    NSArray *args = [NSArray arrayWithObjects:@"/usr/local/bin/autopkg", @"repo-add", [NSString stringWithFormat:@"%@", repoURL], nil];

    // Configure the task
    [autoPkgRepoAddTask setLaunchPath:launchPath];
    [autoPkgRepoAddTask setArguments:args];
    [autoPkgRepoAddTask setStandardOutput:autoPkgRepoAddPipe];
    [autoPkgRepoAddTask setStandardError:[NSPipe pipe]];

    autoPkgRepoAddTask.terminationHandler = ^(NSTask *aTask) {
        NSError *error = nil;
        NSData *errData = [[aTask.standardError fileHandleForReading ]readDataToEndOfFile];
        NSString *errString = [[NSString alloc]initWithData:errData encoding:NSASCIIStringEncoding];
        // autopkg's rc on a failed repo-update is 0, so check the stderr for "ERROR" string
        if ([errString rangeOfString:@"ERROR"].location != NSNotFound) {
            error = [NSError errorWithDomain:[[NSBundle mainBundle] bundleIdentifier]
                                        code:1
                                    userInfo:@{NSLocalizedDescriptionKey:@"Error adding repo",
                                               NSLocalizedRecoverySuggestionErrorKey:errString,
                                               }];
        }
        [[NSNotificationCenter defaultCenter]postNotificationName:kProgressStopNotification
                                                           object:self
                                                         userInfo:error ? @{kNotificationUserInfoError:error}:nil];
    };

    // Launch the task
    [autoPkgRepoAddTask launch];
    [autoPkgRepoAddTask waitUntilExit];
}

- (void)removeAutoPkgRecipeRepo:(NSString *)repoURL
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kProgressStartNotification
                                                        object:nil
                                                      userInfo:@{ kNotificationUserInfoMessage : @"Removing Repo" }];

    // Set up task and pipe
    NSTask *autoPkgRepoRemoveTask = [[NSTask alloc] init];
    NSPipe *autoPkgRepoRemovePipe = [NSPipe pipe];

    // Set up launch path and args
    NSString *launchPath = @"/usr/bin/python";
    NSArray *args = [NSArray arrayWithObjects:@"/usr/local/bin/autopkg", @"repo-delete", [NSString stringWithFormat:@"%@", repoURL], nil];

    // Configure the task
    [autoPkgRepoRemoveTask setLaunchPath:launchPath];
    [autoPkgRepoRemoveTask setArguments:args];
    [autoPkgRepoRemoveTask setStandardOutput:autoPkgRepoRemovePipe];
    [autoPkgRepoRemoveTask setStandardError:[NSPipe pipe]];

    autoPkgRepoRemoveTask.terminationHandler = ^(NSTask *aTask) {
        NSError *error = nil;
        NSData *errData = [[aTask.standardError fileHandleForReading ]readDataToEndOfFile];
        NSString *errString = [[NSString alloc]initWithData:errData encoding:NSASCIIStringEncoding];
        // autopkg's rc on a failed repo-update is 0, so check the stderr for "ERROR" string
        if ([errString rangeOfString:@"ERROR"].location != NSNotFound) {
            error = [NSError errorWithDomain:[[NSBundle mainBundle] bundleIdentifier]
                                        code:1
                                    userInfo:@{NSLocalizedDescriptionKey:@"Error removing repo",
                                               NSLocalizedRecoverySuggestionErrorKey:errString,
                                               }];
        }
        [[NSNotificationCenter defaultCenter]postNotificationName:kProgressStopNotification
                                                           object:self
                                                         userInfo:error ? @{kNotificationUserInfoError:error}:nil];
    };

    // Launch the task
    [autoPkgRepoRemoveTask launch];
    [autoPkgRepoRemoveTask waitUntilExit];
}

- (void)updateAutoPkgRecipeRepos
{
    // Set up task and pipe
    NSTask *updateAutoPkgReposTask = [[NSTask alloc] init];

    // Set up launch path and args
    NSString *launchPath = @"/usr/bin/python";
    NSArray *args = [NSArray arrayWithObjects:@"/usr/local/bin/autopkg", @"repo-update", @"all", nil];

    // Configure the task
    [updateAutoPkgReposTask setLaunchPath:launchPath];
    [updateAutoPkgReposTask setArguments:args];
    [updateAutoPkgReposTask setStandardOutput:[NSPipe pipe]];
    [updateAutoPkgReposTask setStandardError:[NSPipe pipe]];

    updateAutoPkgReposTask.terminationHandler = ^(NSTask *aTask) {
        NSError *error;
        NSData *errData = [[aTask.standardError fileHandleForReading ]readDataToEndOfFile];
        NSString *errString = [[NSString alloc]initWithData:errData encoding:NSASCIIStringEncoding];
        // autopkg's rc on a failed repo-update is 0, so check the stderr for "ERROR" string
        if ([errString rangeOfString:@"ERROR"].location != NSNotFound) {
            error = [NSError errorWithDomain:[[NSBundle mainBundle] bundleIdentifier]
                                        code:1
                                    userInfo:@{NSLocalizedDescriptionKey:@"Error updating autopkg repos",
                                               NSLocalizedRecoverySuggestionErrorKey:errString,
                                               }];
        }

        [[NSNotificationCenter defaultCenter]postNotificationName:kUpdateReposCompleteNotification
                                                           object:self
                                                         userInfo:error ? @{kNotificationUserInfoError:error}:nil];
    };

    // Launch the task
    [updateAutoPkgReposTask launch];
}

- (void)runAutoPkgWithRecipeListAndSendEmailNotificationIfConfigured:(NSString *)recipeListPath
{
    // Determine version so we chan properly handle --report-plist
    BOOL autoPkgAboveV0_3_2;

    LGHostInfo *info = [LGHostInfo new];
    LGVersionComparator *comparator = [LGVersionComparator new];
    if ([comparator isVersion:info.getAutoPkgVersion greaterThanVersion:@"0.3.2"]) {
        autoPkgAboveV0_3_2 = YES;
    }

    // Set up our task, pipe, and file handle
    NSTask *autoPkgRunTask = [[NSTask alloc] init];
    autoPkgRunTask.launchPath = @"/usr/bin/python";
    autoPkgRunTask.standardOutput = [NSPipe pipe];
    autoPkgRunTask.standardError = [NSPipe pipe];

    // Set up args based on wether report is a file or piped to stdout
    NSMutableArray *args = [[NSMutableArray alloc] initWithArray:@[ @"/usr/local/bin/autopkg",
                                                                    @"run",
                                                                    @"--recipe-list",
                                                                    recipeListPath,
                                                                    @"--report-plist" ]];

    NSString *plistFile;
    if (autoPkgAboveV0_3_2) {
        plistFile = [NSTemporaryDirectory() stringByAppendingString:[[NSProcessInfo processInfo] globallyUniqueString]];
        // Add arg for the file path to the report-plist and turn on verbose mode.
        [args addObjectsFromArray:@[ plistFile ]];

        // If the version of AutoPkg is > 0.3.2 we'll be able to provide lots more information
        NSString *recipeListString = [NSString stringWithContentsOfFile:recipeListPath encoding:NSASCIIStringEncoding error:nil];
        NSArray  *recipeListArray = [recipeListString componentsSeparatedByString:@"\n"];
        __block NSInteger installCount = 1;
        NSInteger totalCount = recipeListArray.count;
        [autoPkgRunTask.standardOutput fileHandleForReading].readabilityHandler = ^(NSFileHandle *handle) {
            // Generate the string from the task's avaliable data
            NSString *string = [[NSString alloc ] initWithData:[handle availableData] encoding:NSASCIIStringEncoding];
            // Strip out any new line characters so it displays better
            NSString *strippedString = [string stringByReplacingOccurrencesOfString:@"\n" withString:@""];
            // Add the count of the
            NSString *detailString = [NSString stringWithFormat:@"%@ (%ld/%ld)",strippedString,installCount,totalCount];
            // Post notification
            installCount++;
            [[NSNotificationCenter defaultCenter] postNotificationName:kProgressMessageUpdateNotification
                                                                object:nil
                                                              userInfo:@{kNotificationUserInfoMessage:detailString}];
        };
    }

    autoPkgRunTask.arguments = args;

    autoPkgRunTask.terminationHandler = ^(NSTask *aTask) {
        NSError *error;
        if (aTask.terminationStatus != 0) {
            NSString *errString;
            if(aTask.terminationStatus == 255){
                errString = @"No Recipes Specified.";
            }else{
                NSData *errData = [[aTask.standardError fileHandleForReading ]readDataToEndOfFile];
                if ( errData ){
                    errString = [[NSString alloc]initWithData:errData encoding:NSASCIIStringEncoding];
                }
            }
            error = [NSError errorWithDomain:[[NSBundle mainBundle] bundleIdentifier]
                                        code:aTask.terminationStatus
                                    userInfo:@{NSLocalizedDescriptionKey:@"Error running autopkg",
                                               NSLocalizedRecoverySuggestionErrorKey:errString,}];
        }
        
        [[NSNotificationCenter defaultCenter]postNotificationName:kRunAutoPkgCompleteNotification
                                                           object:self
                                                         userInfo:error ? @{kNotificationUserInfoError:error}:nil];
        
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        // If the autopkg run exited successfully and the send email is enabled continue
        if (aTask.terminationStatus == 0 && [defaults boolForKey:kSendEmailNotificationsWhenNewVersionsAreFoundEnabled]) {
            NSDictionary *plist;
            NSError *error;
            
            // Read our data from file if autopkg v > 0.3.2 else read from stdout filehandle
            if (autoPkgAboveV0_3_2) {
                if (plistFile) {
                    plist = [NSDictionary dictionaryWithContentsOfFile:plistFile];
                }
            } else {
                NSData *autoPkgRunReportPlistData = [[aTask.standardOutput fileHandleForReading] readDataToEndOfFile];
                // Init our string with data from the fileHandle
                NSString *autoPkgRunReportPlistString = [[NSString alloc] initWithData:autoPkgRunReportPlistData encoding:NSUTF8StringEncoding];
                if (![autoPkgRunReportPlistString isEqualToString:@""]) {
                    // Convert string back to data for plist serialization
                    NSData *plistData = [autoPkgRunReportPlistString dataUsingEncoding:NSUTF8StringEncoding];
                    // Initialize plist format
                    NSPropertyListFormat format;
                    // Initialize our dict
                    plist = [NSPropertyListSerialization propertyListWithData:plistData options:NSPropertyListImmutable format:&format error:&error];
                }
            }
            NSLog(@"This is our plist: %@.", plist);
            
            if (!plist) {
                NSLog(@"Could not serialize the plist. Error: %@.", error);
                return;
            }
            
            // Get arrays of new downloads/packages from the plist
            NSArray *newDownloads = [plist objectForKey:@"new_downloads"];
            NSArray *newPackages = [plist objectForKey:@"new_packages"];
            if ([newDownloads count]) {
                NSLog(@"New stuff was downloaded.");
                NSMutableArray *newDownloadsArray = [[NSMutableArray alloc] init];
                
                for (NSString *path in newDownloads) {
                    NSMutableDictionary *newDownloadDict = [[NSMutableDictionary alloc] init];
                    // Get just the application name from the path in the new_downloads dict
                    NSString *app = [[path lastPathComponent] stringByDeletingPathExtension];
                    // Insert the app name into the dictionary for the "app" key
                    [newDownloadDict setObject:app forKey:@"app"];
                    [newDownloadDict setObject:@"N/A" forKey:@"version"];
                    
                    for (NSDictionary *dct in newPackages) {
                        NSString *pkgPath = [dct objectForKey:@"pkg_path"];
                        
                        if ([pkgPath rangeOfString:app options:NSCaseInsensitiveSearch].location != NSNotFound && [dct objectForKey:@"version"]) {
                            NSString *version = [dct objectForKey:@"version"];
                            [newDownloadDict setObject:version forKey:@"version"];
                            break;
                        }
                    }
                    [newDownloadsArray addObject:newDownloadDict];
                }
                
                NSLog(@"New software was downloaded. Sending an email alert.");
                [self sendNewDowloadsEmail:newDownloadsArray];
                
            } else {
                NSLog(@"Nothing new was downloaded.");
            }
        }
    };

    // Launch the task
    [autoPkgRunTask launch];
}

- (void)sendNewDowloadsEmail:(NSArray *)newDownloadsArray
{
    LGEmailer *emailer = [[LGEmailer alloc] init];

    NSMutableArray *apps = [[NSMutableArray alloc] init];

    for (NSDictionary *download in newDownloadsArray) {
        NSString *app = [download objectForKey:@"app"];
        [apps addObject:app];
    }

    // Create the subject string
    NSString *subject = [NSString stringWithFormat:@"[%@] The Following Software Is Now Available for Testing (%@)", kApplicationName, [apps componentsJoinedByString:@", "]];

    // Create the message string
    NSMutableString *newDownloadsString = [NSMutableString string];
    NSEnumerator *e = [newDownloadsArray objectEnumerator];
    id dictionary;
    while ((dictionary = [e nextObject]) != nil)
        [newDownloadsString appendFormat:@"<br /><strong>%@</strong>: %@", [dictionary objectForKey:@"app"], [dictionary objectForKey:@"version"]];
    NSString *message = [NSString stringWithFormat:@"The following software is now available for testing:<br />%@", newDownloadsString];

    [emailer sendEmailNotification:subject message:message];
}

- (void)invokeAutoPkgInBackgroundThread
{
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    // This ensures that no more than one thread will be spawned
    // to run AutoPkg.
    [queue setMaxConcurrentOperationCount:1];
    NSInvocationOperation *task = [[NSInvocationOperation alloc] initWithTarget:self selector:@selector(runAutoPkgWithRecipeList) object:nil];
    [queue addOperation:task];
}

- (void)invokeAutoPkgRepoUpdateInBackgroundThread
{
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    // This ensures that no more than one thread will be spawned
    // to run AutoPkg repo updates.
    [queue setMaxConcurrentOperationCount:1];
    NSInvocationOperation *task = [[NSInvocationOperation alloc] initWithTarget:self selector:@selector(updateAutoPkgRecipeRepos) object:nil];
    [queue addOperation:task];
}

- (void)runAutoPkgWithRecipeList
{
    LGApplications *apps = [[LGApplications alloc] init];
    NSString *applicationSupportDirectory = [apps getAppSupportDirectory];
    NSString *recipeListFilePath = [applicationSupportDirectory stringByAppendingString:@"/recipe_list.txt"];
    [self runAutoPkgWithRecipeListAndSendEmailNotificationIfConfigured:recipeListFilePath];
}

- (void)startAutoPkgRunTimer
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    if ([defaults objectForKey:kCheckForNewVersionsOfAppsAutomaticallyEnabled]) {

        BOOL checkForNewVersionsOfAppsAutomaticallyEnabled = [[defaults objectForKey:kCheckForNewVersionsOfAppsAutomaticallyEnabled] boolValue];

        if (checkForNewVersionsOfAppsAutomaticallyEnabled) {
            if ([defaults integerForKey:kAutoPkgRunInterval]) {
                double i = [defaults integerForKey:kAutoPkgRunInterval];
                if (i != 0) {
                    NSTimeInterval ti = i * 60 * 60; // Convert hours to seconds for our time interval
                    [NSTimer scheduledTimerWithTimeInterval:ti target:self selector:@selector(invokeAutoPkgInBackgroundThread) userInfo:nil repeats:YES];
                } else {
                    NSLog(@"i is 0 because that's what the user entered or what they entered wasn't a digit.");
                }
            } else {
                NSLog(@"The user enabled automatic checking for app updates but they specified no interval.");
            }
        }
    }
}

- (void)setLocalMunkiRepoForAutoPkg:(NSString *)localMunkiRepo
{
    CFStringRef key = (CFSTR("MUNKI_REPO"));
    // Create a CoreFoundation string reference from the
    // localMunkiRepo NSString pointer, (no need to release)
    CFStringRef val = (__bridge CFStringRef)localMunkiRepo;
    CFStringRef appID = (CFSTR("com.github.autopkg"));

    CFPreferencesSetAppValue(key, val, appID);

    // Release our key and appID refs
    CFRelease(key);
    CFRelease(appID);
}

@end
