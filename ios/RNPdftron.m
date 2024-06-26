#import "RNPdftron.h"
#import <React/RCTLog.h>

#import <PDFNet/PDFNet.h>

@implementation RNPdftron

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}
RCT_EXPORT_MODULE()

RCT_EXPORT_METHOD(initialize:(nonnull NSString *)key)
{
    [PTPDFNet Initialize:key];
    RCTLogInfo(@"PDFNet version: %f", [PTPDFNet GetVersion]);
}

RCT_EXPORT_METHOD(enableJavaScript:(BOOL)enabled)
{
    [PTPDFNet EnableJavaScript:enabled];
}

RCT_REMAP_METHOD(encryptDocument,
                 encryptDocumentForFilePath:(NSString *)filePath
                 password:(NSString *)password
                 currentPassword:(NSString *)currentPassword
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
    @try {
        NSString *oldPassword = currentPassword;
        if (!oldPassword) {
            oldPassword = @"";
        }
        
        PTPDFDoc *pdfDoc = [[PTPDFDoc alloc] initWithFilepath:filePath];
        if ([pdfDoc InitStdSecurityHandler:oldPassword]) {
            [self setPassword:password onPDFDoc:pdfDoc];
            [pdfDoc Lock];
            [pdfDoc SaveToFile:filePath flags:e_ptremove_unused];
            [pdfDoc Unlock];
            resolve(nil);
        }
        else {
            reject(@"password", @"Current password is incorrect.", nil);
        }
    }
    @catch (NSException *exception) {
        reject(@"encrypt_failed", @"Failed to encrypt document", [self errorFromException:exception]);
    }
}

RCT_EXPORT_METHOD(getVersion:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
    @try {
        resolve([@"PDFNet " stringByAppendingFormat:@"%f", [PTPDFNet GetVersion]]);
    }
    @catch (NSException *exception) {
        reject(@"get_failed", @"Failed to get PDFNet version", [self errorFromException:exception]);
    }
}


RCT_EXPORT_METHOD(getPlatformVersion:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
    @try {
        resolve([@"iOS " stringByAppendingString:[[UIDevice currentDevice] systemVersion]]);
    }
    @catch (NSException *exception) {
        reject(@"get_failed", @"Failed to get platform version", [self errorFromException:exception]);
    }
}

- (void)setPassword:(NSString *)password onPDFDoc:(PTPDFDoc *)pdfDoc
{
    if (!pdfDoc) {
        return;
    }
    
    BOOL shouldUnlock = NO;
    @try {
        [pdfDoc Lock];
        shouldUnlock = YES;
        
        // remove all security on the document
        [pdfDoc RemoveSecurity];
        if (password.length > 0) {
            // Set a new password required to open a document
            PTSecurityHandler *newHandler = [[PTSecurityHandler alloc] initWithCrypt_type:e_ptAES];
            [newHandler ChangeUserPassword:password];
            
            // Set Permissions
            [newHandler SetPermission:e_ptprint value:YES];
            
            // Note: document takes ownership of newHandler
            [pdfDoc SetSecurityHandler:newHandler];
        }
    }
    @catch (NSException *exception) {
        NSLog(@"Exception: %@, %@", exception.name, exception.reason);
    }
    @finally {
        if (shouldUnlock) {
            [pdfDoc Unlock];
        }
    }
}

RCT_EXPORT_METHOD(pdfFromOffice:(NSString *)docxPath options:(NSDictionary*)options resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    @try {
        PTPDFDoc* pdfDoc = [[PTPDFDoc alloc] init];
        PTOfficeToPDFOptions* conversionOptions = [[PTOfficeToPDFOptions alloc] init];
        
        if (options != Nil) {
            if (options[@"applyPageBreaksToSheet"]) {
                [conversionOptions SetApplyPageBreaksToSheet:[[options objectForKey:@"applyPageBreaksToSheet"] boolValue]];
            }
            
            if (options[@"displayChangeTracking"]) {
                [conversionOptions SetDisplayChangeTracking:[[options objectForKey:@"displayChangeTracking"] boolValue]];
            }
            
            if (options[@"excelDefaultCellBorderWidth"]) {
                [conversionOptions SetExcelDefaultCellBorderWidth:[[options objectForKey:@"excelDefaultCellBorderWidth"] doubleValue]];
            }
            
            if (options[@"excelMaxAllowedCellCount"]) {
                [conversionOptions SetExcelMaxAllowedCellCount:[[options objectForKey:@"excelMaxAllowedCellCount"] doubleValue]];
            }
            
            if (options[@"locale"]) {
                [conversionOptions SetLocale:[[options objectForKey:@"locale"] stringValue]];
            }

        }
        
        [PTConvert OfficeToPDF:pdfDoc in_filename:docxPath options:conversionOptions];
        
        NSString* fileName = [[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"pdf"];
        NSString* resultPdfPath = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
        
        BOOL shouldUnlock = NO;
        @try {
            [pdfDoc Lock];
            shouldUnlock = YES;
            
            [pdfDoc SaveToFile:resultPdfPath flags:0];
        } @catch (NSException* exception) {
            NSLog(@"Exception: %@: %@", exception.name, exception.reason);
        } @finally {
            if (shouldUnlock) {
                [pdfDoc Unlock];
            }
        }

        resolve(resultPdfPath);
    }
    @catch (NSException *exception) {
        NSLog(@"Exception: %@, %@", exception.name, exception.reason);
        reject(@"generation_failed", @"Failed to generate document from Office doc", [self errorFromException:exception]);
    }    
}

RCT_EXPORT_METHOD(pdfFromOfficeTemplate:(NSString *)docxPath json:(NSDictionary *)json resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    @try {
        PTPDFDoc* pdfDoc = [[PTPDFDoc alloc] init];
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        PTOfficeToPDFOptions* options = [[PTOfficeToPDFOptions alloc] init];
        [options SetTemplateParamsJson:jsonString];
        [PTConvert OfficeToPDF:pdfDoc in_filename:docxPath options:options];
        
        NSString* fileName = [[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"pdf"];
        NSString* resultPdfPath = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
        
        BOOL shouldUnlock = NO;
        @try {
            [pdfDoc Lock];
            shouldUnlock = YES;
            
            [pdfDoc SaveToFile:resultPdfPath flags:0];
        } @catch (NSException* exception) {
            NSLog(@"Exception: %@: %@", exception.name, exception.reason);
        } @finally {
            if (shouldUnlock) {
                [pdfDoc Unlock];
            }
        }

        resolve(resultPdfPath);
    }
    @catch (NSException *exception) {
        NSLog(@"Exception: %@, %@", exception.name, exception.reason);
        reject(@"generation_failed", @"Failed to generate document from template", [self errorFromException:exception]);
    }    
}

RCT_EXPORT_METHOD(exportAsImage:(int)pageNumber
                  dpi:(int)dpi
                  exportFormat:(NSString*)exportFormat
                  filePath:(NSString*)filePath
                  transparent:(BOOL)transparent
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    @try {
        PTPDFDoc * doc = [[PTPDFDoc alloc] initWithFilepath:filePath];
        NSString * resultImagePath = [RNPdftron exportAsImageHelper:doc pageNumber:pageNumber dpi:dpi exportFormat:exportFormat transparent:transparent];
        
        resolve(resultImagePath);
    }
    @catch (NSException* exception) {
        NSLog(@"Exception: %@, %@", exception.name, exception.reason);
        reject(@"generation_failed", @"Failed to generate image from file", [self errorFromException:exception]);
    }
}

RCT_EXPORT_METHOD(convertHtmlToPdf:(NSString*)htmlStr baseUrl:(NSString*)baseUrl resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
 @try {
  NSURL *url = [[NSURL alloc] initWithString:baseUrl];
  [PTConvert convertHTMLStringToPDF:htmlStr baseURL:url paperSize:CGSizeZero completion:^(NSString *pathToPDF) {
   if (!pathToPDF) {
    // Failed to convert HTML to PDF.
    return;
   }
    NSString* tempDir = NSTemporaryDirectory();
   NSString *documentDirectory = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
   // Copy temporary PDF to temp directory.
   NSURL *urlToPDF = [NSURL fileURLWithPath:pathToPDF];
   NSString *guid = [[NSProcessInfo processInfo] globallyUniqueString] ;
   NSString *ext = [urlToPDF pathExtension];
   NSString *uniqueFileName = [NSString stringWithFormat:@"%@.%@", guid , ext];
   NSURL *destinationURL = [[NSURL fileURLWithPath:tempDir] URLByAppendingPathComponent: uniqueFileName];
   NSLog(@"URl: %@", destinationURL.absoluteURL);
   NSError *error = nil;
   BOOL result = [NSFileManager.defaultManager copyItemAtURL:urlToPDF toURL:destinationURL error:&error];
   if (!result) {
    // Failed to copy PDF to persistent location.
    // reject(@"generation_failed", @"Failed to generate pdf from html", nil);
   }
   // Do something with PDF output.
   resolve(destinationURL.absoluteString);
  }];
 }
 @catch (NSException* exception) {
  NSLog(@"Exception: %@, %@", exception.name, exception.reason);
  reject(@"generation_failed", @"Failed to generate pdf from html", [self errorFromException:exception]);
 }
}
RCT_EXPORT_METHOD(mergeDocuments:(NSArray *)documentsArray resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
  @try
  {
    PTPDFDoc *new_doc = [[PTPDFDoc alloc] init];
    [new_doc InitSecurityHandler];
    NSString* tempDir = NSTemporaryDirectory();
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (id doc in documentsArray) {
      @try {
        PTPDFDoc *in_doc = [[PTPDFDoc alloc] initWithFilepath: doc];
        [new_doc InsertPages:[new_doc GetPageCount]+1 src_doc:in_doc start_page:1 end_page:[in_doc GetPageCount] flag:e_ptinsert_none];
        NSURL *tempDoc = [NSURL fileURLWithPath:doc];
        NSString *filePath = [tempDir stringByAppendingPathComponent:tempDoc.lastPathComponent];
        if ([fileManager fileExistsAtPath:filePath]) {
          NSError *error = nil;
           if ([fileManager removeItemAtPath:filePath error:&error]) {
             NSLog(@"File deleted successfully.");
           } else {
             NSLog(@"Error deleting file: %@", error);
           }
        }
      }
      @catch(NSException *exception)
      {
        NSLog(@"Error repairing document: %@", exception.reason);
        continue;
      }
    };
    NSString* fileName = [NSUUID UUID].UUIDString;
    NSString* resultDocPath = [tempDir stringByAppendingPathComponent:fileName];
    resultDocPath = [resultDocPath stringByAppendingPathExtension:@"pdf"];
    [new_doc SaveToFile: resultDocPath flags: e_ptremove_unused];
    NSLog(@"Done. Result saved in newsletter_merge_pages.pdf");
    resolve(resultDocPath);
  }
  @catch(NSException *exception)
  {
    reject(@"merging_failed", @"Failed to merge documents", [self errorFromException:exception]);
  }
}
RCT_EXPORT_METHOD(createStamper:(NSString*)filePath
                  stampText:(NSString*)stampText
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    @try {
        PTPDFDoc * doc = [[PTPDFDoc alloc] initWithFilepath:filePath];
        
        PTStamper *s = [[PTStamper alloc] initWithSize_type: e_ptrelative_scale a: 0.05 b: 0.05];
        [doc InitSecurityHandler];
        [s SetAlignment: e_pthorizontal_center vertical_alignment: e_ptvertical_bottom];
        [s SetPosition: 0 vertical_distance: 5 use_percentage: false];
        [s SetFont: [PTFont Create: [doc GetSDFDoc] type: e_pthelvetica embed: YES]];
        [s SetSize: e_pts_font_size a: 9 b: -1];
        [s SetTextAlignment: e_ptalign_center];
        for (int page = 1; page <= [doc GetPageCount]; page++)
        {
            NSString *pageText = [NSString stringWithFormat:@"%@Page %i of %i",stampText,page,[doc GetPageCount]];
            PTPageSet *page_ps = [[PTPageSet alloc] initWithOne_page: page];
            [s StampText: doc src_txt: pageText dest_pages: page_ps];
        }
        [doc SaveToFile: filePath flags: e_ptremove_unused];
        resolve(filePath);
    }
    @catch (NSException* exception) {
        NSLog(@"Exception: %@, %@", exception.name, exception.reason);
        reject(@"generation_failed", @"Failed to generate stamp", [self errorFromException:exception]);
    }
}
- (NSError *)errorFromException:(NSException *)exception
{
    return [NSError errorWithDomain:@"com.pdftron.react-native" code:0 userInfo:
            @{
                NSLocalizedDescriptionKey: exception.name,
                NSLocalizedFailureReasonErrorKey: exception.reason,
            }];
}

+(NSString*)exportAsImageHelper:(PTPDFDoc*)doc pageNumber:(int)pageNumber dpi:(int)dpi exportFormat:(NSString*)exportFormat transparent:(BOOL)transparent
{
    NSString * resultImagePath = nil;
    BOOL shouldUnlock = NO;
    @try {
        [doc LockRead];
        shouldUnlock = YES;

        if (pageNumber <= [doc GetPageCount] && pageNumber >= 1) {
            PTPDFDraw *draw = [[PTPDFDraw alloc] initWithDpi:dpi];
            [draw SetPageTransparent:transparent];
            NSString* tempDir = NSTemporaryDirectory();
            NSString* fileName = [NSUUID UUID].UUIDString;
            resultImagePath = [tempDir stringByAppendingPathComponent:fileName];
            resultImagePath = [resultImagePath stringByAppendingPathExtension:exportFormat];
            PTPage * exportPage = [doc GetPage:pageNumber];
            [draw Export:exportPage filename:resultImagePath format:exportFormat];
        }
    } @catch (NSException *exception) {
        NSLog(@"Exception: %@: %@", exception.name, exception.reason);
    } @finally {
        if (shouldUnlock) {
            [doc UnlockRead];
        }
    }
    return resultImagePath;
}



@end
  
