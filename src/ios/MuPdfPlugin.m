#import "MuPdfPlugin.h"

#import <mupdf/MuDocRef.h>
#import "DocumentController.h"
#include <mupdf/fits.h>
#include <mupdf/common.h>

@implementation MuPdfPlugin
{
  MuDocRef *doc;
  char *_filePath;
  CDVInvokedUrlCommand* cdvCommand;
}

enum
{
    // use at most 128M for resource cache
    ResourceCacheMaxSize = 128<<20	// use at most 128M for resource cache
};

- (void)pluginInitialize
{
    queue = dispatch_queue_create("com.artifex.mupdf.queue", NULL);

    screenScale = [[UIScreen mainScreen] scale];

    ctx = fz_new_context(NULL, NULL, ResourceCacheMaxSize);
    fz_register_document_handlers(ctx);
}

- (void)openPdf:(CDVInvokedUrlCommand*)command
{
  CDVPluginResult* pluginResult = nil;
  NSString* path = [command.arguments objectAtIndex:0];
  NSString* documentTitle = [command.arguments objectAtIndex:1];
  NSDictionary *options = [command argumentAtIndex:2];

  cdvCommand = command;

  NSUrl *url = [NSUrl URLWithString:path];
  if (url != nil) {
    if ([url isFileURL]) {
      path = [url path];
    } else {
      path = nil;
    }
  }

  if (path != nil && [path length] > 0) {
    [self openDocument:path title:documentTitle options:options];
  } else {
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
  }
}

- (void) openDocument:(NSString*)path title:(NSString*)documentTitle options:(NSDictionary*)options
{
  doc = [[MuDocRef alloc] initWithFilename:path];
  if (!doc) {
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:cdvCommand.callbackId];
    return;
  }

  DocumentController *document = [[DocumentController alloc] initWithFilename:documentTitle path:path document:doc options:options];
  if (document) {
    UINavigationController* navigator = [[UINavigationController alloc] initWithRootViewController:document];
    [[navigator navigationBar] setTranslucent: YES];
    [[navigator toolbar] setTranslucent: YES];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didDismissDocumentController:) name:@"DocumentControllerDismissed" object:nil];

    [self.viewController presentViewController:navigationController animated:YES completion:nil];
  }

  free(_filePath);
}

-(void)didDismissDocumentController:(NSNotification *)notification {
  NSDictionary* saveResults = [notification object];
  CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:saveResults];
  [self.commandDelegate sendPluginResult:pluginResult callbackId:cdvCommand.callbackId];
}

@end
