#undef ABS
#undef MIN
#undef MAX

#import <mupdf/MuDocumentController.h>

@interface DocumentController : MuDocumentController
- (instancetype) initWithFilename:(NSString*)filename path:(NSString *)path document:(MuDocRef *)aDoc options:(NSDictionary*)options;
@end
