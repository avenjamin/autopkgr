//
//  LGAppDelegate.m
//  AutoPkgr
//
//  Created by James Barclay on 6/25/14.
//  Copyright (c) 2014 The Linde Group, Inc. All rights reserved.
//

#import "LGAppDelegate.h"
#import "LGConstants.h"
#import "LGAutoPkgrHelperConnection.h"
#import "LGConfigurationWindowController.h"
#import "AHLaunchCTL.h"

@implementation LGAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [self setupStatusItem];

    // Show the configuration window if we haven't
    // completed the initial setup
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kHasCompletedInitialSetup]) {

        BOOL hasCompletedInitialSetup = [[defaults objectForKey:kHasCompletedInitialSetup] boolValue];

        if (!hasCompletedInitialSetup) {
            [self showConfigurationWindow:nil];
        }
    } else {
        [self showConfigurationWindow:nil];
    }
    
    NSError *error;
    if (![AHLaunchCtl installHelper:kHelperName prompt:@"To schedule" error:&error]) {
        if (error) {
            NSLog(@"%@", error.localizedDescription);
            [NSApp presentError:error];
            [self applicationShouldTerminate:nil];
        }
    }
    
    // Start the AutoPkg run timer if the user enabled it
    [self startAutoPkgRunTimer];

    // Update AutoPkg recipe repos when the application launches
    // if the user has enabled automatic repo updates
    if ([defaults objectForKey:kCheckForRepoUpdatesAutomaticallyEnabled]) {

        BOOL checkForRepoUpdatesAutomaticallyEnabled = [[defaults objectForKey:kCheckForRepoUpdatesAutomaticallyEnabled] boolValue];

        if (checkForRepoUpdatesAutomaticallyEnabled) {
            NSLog(@"Updating AutoPkg recipe repos.");
            [self updateAutoPkgRecipeReposInBackgroundAtAppLaunch];
        }
    }
}

- (void)startAutoPkgRunTimer
{
    LGAutoPkgRunner *autoPkgRunner = [[LGAutoPkgRunner alloc] init];
    [autoPkgRunner startAutoPkgRunTimer];
}

- (void)updateAutoPkgRecipeReposInBackgroundAtAppLaunch
{
    LGAutoPkgRunner *autoPkgRunner = [[LGAutoPkgRunner alloc] init];
    [autoPkgRunner invokeAutoPkgRepoUpdateInBackgroundThread];
}

- (void)setupStatusItem
{
    // Setup the systemStatusBar
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    [self.statusItem setMenu:self.statusMenu];
    [self.statusItem setImage:[NSImage imageNamed:@"autopkgr.png"]];
    [self.statusItem setAlternateImage:[NSImage imageNamed:@"autopkgr_alt.png"]];
    [self.statusItem setHighlightMode:YES];
    [self setupMenu];
}

- (void)setupMenu
{
    // Setup menu items for statusItem
    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:@"Check Now" action:@selector(checkNowFromMenu:) keyEquivalent:@""];

    [menu addItemWithTitle:@"Configure..." action:@selector(showConfigurationWindow:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:[NSString stringWithFormat:@"Quit %@", kApplicationName] action:@selector(terminate:) keyEquivalent:@""];
    
    NSMenuItem *uninstallHelper = [[NSMenuItem alloc]initWithTitle:@"Uninstall" action:@selector(uninstallHelper:) keyEquivalent:@""];
    uninstallHelper.keyEquivalentModifierMask = NSControlKeyMask;
    uninstallHelper.alternate = YES;
    [menu addItem:uninstallHelper];
    
    self.statusItem.menu = menu;
}

- (void)checkNowFromMenu:(id)sender
{
    LGAutoPkgRunner *autoPkgRunner = [[LGAutoPkgRunner alloc] init];
    [autoPkgRunner invokeAutoPkgInBackgroundThread];
}

- (void)showConfigurationWindow:(id)sender
{
    if (!configurationWindowController) {
        configurationWindowController = [[LGConfigurationWindowController alloc] initWithWindowNibName:@"LGConfigurationWindowController"];
    }
    [configurationWindowController showWindow:self];
}

- (IBAction)uninstallHelper:(id)sender{
    LGAutoPkgrHelperConnection *helper = [LGAutoPkgrHelperConnection new];
    [helper connectToHelper];
    [[helper.connection remoteObjectProxy] uninstall:^(NSError *error) {
        if(error){
            [NSApp presentError:error];
        }
    }];
}


- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL warnBeforeQuitting = [[defaults objectForKey:kWarnBeforeQuittingEnabled] boolValue];

    if (warnBeforeQuitting) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert addButtonWithTitle:@"Quit"];
        [alert addButtonWithTitle:@"Cancel"];
        [alert setMessageText:[NSString stringWithFormat:@"Are you sure you want to quit %@?", kApplicationName]];
        [alert setInformativeText:[NSString stringWithFormat:@"%@ will not be able to run AutoPkg in the background or send email notifications until you relaunch the application.", kApplicationName]];
        [alert setAlertStyle:NSWarningAlertStyle];

        if ([alert runModal] == NSAlertSecondButtonReturn) {
            NSLog(@"User cancelled quit.");
            return NSTerminateCancel;
        }
    }

    LGAutoPkgrHelperConnection *helper = [LGAutoPkgrHelperConnection new];
    [helper connectToHelper];
    [[helper.connection remoteObjectProxy] quitHelper:^(BOOL success) {}];

    return NSTerminateNow;
}

@end
