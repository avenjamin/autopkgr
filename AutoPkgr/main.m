//
//  main.m
//  AutoPkgr
//
//  Created by James Barclay on 6/25/14.
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

#import <Cocoa/Cocoa.h>
#import "LGAutoPkgTask.h"
#import "LGRecipes.h"
#import "LGEmailer.h"
#import "LGAutoPkgr.h"
#import <pwd.h>

static NSString *const kRootUser = @"root";

NSString *userHomeDir(NSString *user)
{
    struct passwd *ss = getpwnam(user.UTF8String);
    struct passwd *pw = getpwuid(ss->pw_uid);
    return [NSString stringWithUTF8String:pw->pw_dir];
}

NSString *libraryFolder(NSString *user)
{
    return [userHomeDir(user) stringByAppendingPathComponent:@"Library"];
}

NSString *preferencesFolder(NSString *user)
{
    return [libraryFolder(user) stringByAppendingPathComponent:@"Preferences"];
}

NSString *applicationSupportFolder(NSString *user)
{
    return [libraryFolder(user) stringByAppendingPathComponent:@"Application Support"];
}

NSString *autoPkgFolder(NSString *user)
{
    return [libraryFolder(user) stringByAppendingPathComponent:@"AutoPkg"];
}

NSString *autoPkgrFolder(NSString *user)
{
    return [applicationSupportFolder(user) stringByAppendingPathComponent:@"AutoPkgr"];
}

void migratePreferences(NSArray *preferences, NSString *fromUser)
{

    NSString *userPreferenceFolder = preferencesFolder(fromUser);

    for (NSString *pref in preferences) {

        // Make sure the pref is a .plist
        NSString *ePref = pref;
        if (![pref.pathExtension isEqualToString:@"plist"]) {
            ePref = [pref stringByAppendingPathExtension:@"plist"];
        }

        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:[userPreferenceFolder stringByAppendingPathComponent:ePref]];

        // Now that the file is created, register it with cfprefsd
        NSLog(@"Registering Defaults: %@", pref);
        NSUserDefaults *defaults = [NSUserDefaults new];

        [defaults setPersistentDomain:dict forName:pref];
        if (![defaults synchronize]) {
            NSLog(@"There was a problem synchronizing the pref");
        }
    }
}

BOOL backupAndLink(NSString *source, NSString *dest)
{
    NSLog(@"Linking %@", dest);
    NSFileManager *fm = [NSFileManager new];
    NSError *error;
    if ([fm fileExistsAtPath:dest]) {
        if (![fm moveItemAtPath:dest toPath:[dest stringByAppendingPathExtension:@"old"] error:&error]) {
            NSLog(@"ERROR: %@", error.localizedDescription);
            return NO;
        }
    }
    return [fm createSymbolicLinkAtPath:dest withDestinationPath:source error:&error];
}

BOOL restoreLinkedBackup(NSString *originalPath)
{
    // Restore the backup link.  Pass in the name that should be restored;
    NSError *error;
    NSFileManager *fm = [NSFileManager new];
    NSString *backupFile = [originalPath stringByAppendingPathExtension:@"old"];

    // If file exists at original path, see if it's a symbolic link
    if ([fm fileExistsAtPath:originalPath]) {
        NSDictionary *attributes = [fm attributesOfItemAtPath:originalPath error:nil];
        if ([attributes[@"NSFileType"] isEqualToString:NSFileTypeSymbolicLink]) {
            // If it is a symbolic link remove it
            NSLog(@"Removing symlink");
            if (![fm removeItemAtPath:originalPath error:&error]) {
                // Return NO on failure
                NSLog(@"%@", error.localizedDescription);
                return NO;
            }
        }
    }
    // If there is a backup, and not the original path
    if ([fm fileExistsAtPath:backupFile] && ![fm fileExistsAtPath:originalPath]) {
        if (![fm moveItemAtPath:backupFile toPath:originalPath error:&error]) {
            NSLog(@"%@", error.localizedDescription);
            return NO;
        } else {
            NSLog(@"Restored backup of %@", backupFile);
        }
    }
    return YES;
}

BOOL setFolderOwnerRecursively(NSString *user, NSString *path)
{
    NSLog(@"Resetting ownership: %@ ", path);
    NSLog(@"Setting owner as: %@ ", user);

    NSFileManager *fileManager = [NSFileManager new];

    NSArray *subPaths = [fileManager subpathsAtPath:path];
    NSDictionary *attributes = @{ NSFileOwnerAccountName : user };

    for (NSString *aPath in subPaths) {
        NSString *fullPath = [path stringByAppendingPathComponent:aPath];
        if ([fileManager fileExistsAtPath:fullPath isDirectory:nil]) {
            NSError *error = nil;
            [fileManager setAttributes:attributes ofItemAtPath:fullPath error:&error];
            if (error) {
                NSLog(@"Perm Error: %@", error.localizedDescription);
            }
        }
    }

    return YES;
}

BOOL setupRootContext(NSString *user)
{
    NSLog(@"Setting up root context");
    // Copy the Preferences for AutoPkg and AutoPkgr
    // So NSUserDefaults has the correct values when run as root
    migratePreferences(@[ kLGAutoPkgPreferenceDomain, kLGAutoPkgrPreferenceDomain ], user);

    // Create symlink for AutoPkg and AutoPkgr
    NSLog(@"Linking AutoPkg folders");
    if (!backupAndLink(autoPkgFolder(user), autoPkgFolder(kRootUser))) {
        NSLog(@"Problem creating link for autopkgr");
    };

    NSLog(@"Linking AutoPkgr folders");
    if (!backupAndLink(autoPkgrFolder(user), autoPkgrFolder(kRootUser))) {
        NSLog(@"Problem creating link for autopkgr");
    };

    return YES;
}

NSString *ownerOfItemAtPath(NSString *folderPath)
{
    NSFileManager *manager = [NSFileManager new];
    NSDictionary *attrs = [manager attributesOfItemAtPath:folderPath error:nil];
    return attrs[NSFileOwnerAccountName];
}

void cleanUpRootContext(NSString *user)
{
    NSLog(@"Cleaning up root context");

    // Remove the symbolic links, and restore if there was a backup
    restoreLinkedBackup(autoPkgFolder(kRootUser));
    restoreLinkedBackup(autoPkgrFolder(kRootUser));

    // Reset Folders created by root to their proper permissions
    setFolderOwnerRecursively(user, autoPkgFolder(user));

    // Fix AutoPkg's CACHE_DIR Directory as well
    LGDefaults *defaults = [[LGDefaults alloc] init];
    NSString *cacheDir = defaults.autoPkgCacheDir;

    if (cacheDir) {
        // Don't assume the user this is running as is the same
        // as the cache dir's owner, in the case of a shared env
        NSString *currentOwner = ownerOfItemAtPath(cacheDir);
        setFolderOwnerRecursively(currentOwner, cacheDir);
    }
}

int main(int argc, const char *argv[])
{
    NSUserDefaults *args = [NSUserDefaults standardUserDefaults];
    if ([args boolForKey:@"runInBackground"]) {
        NSLog(@"Running AutoPkgr in background...");

        __block LGEmailer *emailer = [[LGEmailer alloc] init];
        LGDefaults *defaults = [LGDefaults standardUserDefaults];
        LGAutoPkgTaskManager *manager = [[LGAutoPkgTaskManager alloc] init];
        [manager runRecipeList:[LGRecipes recipeList]
                    updateRepo:defaults.checkForRepoUpdatesAutomaticallyEnabled
                         reply:^(NSDictionary *report, NSError *error) {
            [emailer sendEmailForReport:report error:error];
                         }];

        while (emailer && !emailer.complete) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
        }

    } else {
        return NSApplicationMain(argc, argv);
    }
}
