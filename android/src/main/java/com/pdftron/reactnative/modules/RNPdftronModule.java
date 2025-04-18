package com.pdftron.reactnative.modules;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.bridge.ReadableArray;
import com.facebook.react.bridge.ReadableMap;
import com.pdftron.pdf.Convert;
import com.pdftron.pdf.Font;
import com.pdftron.pdf.OfficeToPDFOptions;
import com.pdftron.pdf.PDFDoc;
import com.pdftron.pdf.PDFNet;
import com.pdftron.pdf.PageSet;
import com.pdftron.pdf.Stamper;
import com.pdftron.pdf.model.StandardStampOption;
import com.pdftron.pdf.utils.AppUtils;
import com.pdftron.pdf.utils.HTML2PDF;
import com.pdftron.pdf.utils.PdfViewCtrlSettingsManager;
import com.pdftron.pdf.utils.PdfViewCtrlTabsManager;
import com.pdftron.pdf.utils.RecentFilesManager;
import com.pdftron.pdf.utils.Utils;
import com.pdftron.pdf.utils.ViewerUtils;
import com.pdftron.reactnative.utils.ReactUtils;
import com.pdftron.sdf.SDFDoc;

import java.io.File;

public class RNPdftronModule extends ReactContextBaseJavaModule {

    private static final String REACT_CLASS = "RNPdftron";

    public RNPdftronModule(ReactApplicationContext reactContext) {
        super(reactContext);
    }

    @Override
    public String getName() {
        return REACT_CLASS;
    }

    @ReactMethod
    public void initialize(@NonNull String key) {
        try {
            AppUtils.initializePDFNetApplication(getReactApplicationContext(), key);
        } catch (Exception ex) {
            ex.printStackTrace();
        }
    }

    @ReactMethod
    public void enableJavaScript(boolean enabled) {
        try {
            PDFNet.enableJavaScript(enabled);
        } catch (Exception ex) {
            ex.printStackTrace();
        }
    }

    @ReactMethod
    public void getSystemFontList(final Promise promise) {
        String fontList = null;
        Exception exception = null;
        try {
            fontList = PDFNet.getSystemFontList();
        } catch (Exception e) {
            exception = e;
        }

        String finalFontList = fontList;
        Exception finalException = exception;
        getReactApplicationContext().runOnUiQueueThread(new Runnable() {

            @Override
            public void run() {
                if (finalFontList != null) {
                    promise.resolve(finalFontList);
                } else {
                    promise.reject(finalException);
                }
            }
        });
    }

    @ReactMethod
    public void mergeDocuments(ReadableArray documentsArray, final Promise promise) {
        try {
            PDFDoc newDoc = new PDFDoc();
            newDoc.initSecurityHandler();

            for (int i = 0; i < documentsArray.size(); i++) {
                String filePath = documentsArray.getString(i);
                try (PDFDoc inDoc = new PDFDoc(filePath)) {
                    inDoc.initSecurityHandler();
                    newDoc.insertPages(newDoc.getPageCount() + 1, inDoc, 1, inDoc.getPageCount(), PDFDoc.InsertBookmarkMode.NONE, null);
                } catch (Exception e) {
                    e.printStackTrace();
                    continue;
                }
            }

            File resultFile = File.createTempFile("merged_", ".pdf", getReactApplicationContext().getCacheDir());
            String resultDocPath = resultFile.getAbsolutePath();
            newDoc.save(resultDocPath, SDFDoc.SaveMode.REMOVE_UNUSED, null);
            newDoc.close();

            promise.resolve(resultDocPath);
        } catch (Exception e) {
            promise.reject("merging_failed", "Failed to merge documents", e);
        }
    }

    @ReactMethod
    public void convertHtmlToPdf(final String htmlString, final String baseUrl, final Promise promise) {
        getReactApplicationContext().runOnUiQueueThread(new Runnable() {
            @Override
            public void run() {
                final int maxRetries = 2;
                final int[] retryCount = {0};
                
                // Start the first attempt
                attemptConversion(htmlString, baseUrl, promise, maxRetries, retryCount);
            }
            
            private void attemptConversion(final String htmlString, final String baseUrl, 
                                          final Promise promise, final int maxRetries, final int[] retryCount) {
                // Create a flag to track if any callback was called
                final boolean[] callbackCalled = {false};
                
                // Set a timeout to retry if neither callback is called
                final android.os.Handler timeoutHandler = new android.os.Handler();
                final Runnable timeoutRunnable = new Runnable() {
                    @Override
                    public void run() {
                        if (!callbackCalled[0]) {
                            // No callback was called, so we'll retry
                            if (retryCount[0] < maxRetries) {
                                retryCount[0]++;
                                // Add a small delay before retrying (500ms)
                                new android.os.Handler().postDelayed(new Runnable() {
                                    @Override
                                    public void run() {
                                        attemptConversion(htmlString, baseUrl, promise, maxRetries, retryCount);
                                    }
                                }, 500);
                            } else {
                                // Reject the promise if all retries failed
                                promise.reject("conversion_timeout", "Conversion timed out after " + maxRetries + " attempts");
                            }
                        }
                    }
                };
                
                // Set a 20-second timeout
                timeoutHandler.postDelayed(timeoutRunnable, 20000);
                
                try {
                    HTML2PDF.fromHTMLDocument(getReactApplicationContext(), baseUrl, htmlString, new HTML2PDF.HTML2PDFListener() {
                        @Override
                        public void onConversionFinished(String pdfOutput, boolean isLocal) {
                            // Mark that a callback was called
                            callbackCalled[0] = true;
                            // Cancel the timeout
                            timeoutHandler.removeCallbacks(timeoutRunnable);
                            // Resolve the promise with the path to the generated PDF
                            promise.resolve(pdfOutput);
                        }

                        @Override
                        public void onConversionFailed(String error) {
                            // Mark that a callback was called
                            callbackCalled[0] = true;
                            // Cancel the timeout
                            timeoutHandler.removeCallbacks(timeoutRunnable);
                            
                            // Check if we should retry
                            if (retryCount[0] < maxRetries) {
                                retryCount[0]++;
                                // Add a small delay before retrying (500ms)
                                new android.os.Handler().postDelayed(new Runnable() {
                                    @Override
                                    public void run() {
                                        attemptConversion(htmlString, baseUrl, promise, maxRetries, retryCount);
                                    }
                                }, 500);
                            } else {
                                // Reject the promise if all retries failed
                                promise.reject("conversion_failed", "Failed after " + maxRetries + " attempts: " + error);
                            }
                        }
                    });
                } catch (Exception ex) {
                    // Mark that a callback was called (via exception)
                    callbackCalled[0] = true;
                    // Cancel the timeout
                    timeoutHandler.removeCallbacks(timeoutRunnable);
                    
                    // Check if we should retry
                    if (retryCount[0] < maxRetries) {
                        retryCount[0]++;
                        // Add a small delay before retrying (500ms)
                        new android.os.Handler().postDelayed(new Runnable() {
                            @Override
                            public void run() {
                                attemptConversion(htmlString, baseUrl, promise, maxRetries, retryCount);
                            }
                        }, 500);
                    } else {
                        // Reject the promise if all retries failed
                        promise.reject("conversion_error", "Failed after " + maxRetries + " attempts: " + ex.getMessage());
                    }
                }
            }
        });
    }

    @ReactMethod
    public void createStamper(String filePath, String stampText, final Promise promise) {
        try {
            PDFDoc doc = new PDFDoc(filePath);
            doc.initSecurityHandler();

            Stamper stamper = new Stamper(Stamper.e_relative_scale, 0.05, 0.05);

            stamper.setAlignment(Stamper.e_horizontal_center, Stamper.e_vertical_bottom);

            stamper.setPosition(0, 5);

            stamper.setSize(Stamper.e_font_size, 9, -1);


            Font font = Font.create(doc.getSDFDoc(), Font.e_helvetica, true);
            stamper.setFont(font);


            stamper.setTextAlignment(Stamper.e_align_center);

            int pageCount = doc.getPageCount();
            for (int page = 1; page <= pageCount; page++) {
                String pageText = stampText + " Page " + page + " of " + pageCount;
                PageSet pageSet = new PageSet(page);
                stamper.stampText(doc, pageText, pageSet);
            }
            doc.save(filePath, SDFDoc.SaveMode.REMOVE_UNUSED, null);
            doc.close();

            promise.resolve(filePath);


        } catch (Exception ex) {
            promise.reject("generation_failed", "Failed to generate stamp", ex);
        }
    }

    @ReactMethod
    public void clearRubberStampCache(final Promise promise) {
        StandardStampOption.clearCache(getReactApplicationContext());
        getReactApplicationContext().runOnUiQueueThread(new Runnable() {
            @Override
            public void run() {
                promise.resolve(null);
            }
        });
    }

    @ReactMethod
    public void encryptDocument(final String filePath, final String password, final String currentPassword, final Promise promise) {
        try {
            String oldPassword = currentPassword;
            if (Utils.isNullOrEmpty(currentPassword)) {
                oldPassword = "";
            }
            PDFDoc pdfDoc = new PDFDoc(filePath);
            if (pdfDoc.initStdSecurityHandler(oldPassword)) {
                ViewerUtils.passwordDoc(pdfDoc, password);
                pdfDoc.lock();
                pdfDoc.save(filePath, SDFDoc.SaveMode.REMOVE_UNUSED, null);
                pdfDoc.unlock();
                promise.resolve(null);
            } else {
                promise.reject("password", "Current password is incorrect.");
            }
        } catch (Exception ex) {
            promise.reject(ex);
        }
    }

    @ReactMethod
    public void getVersion(final Promise promise) {
        getReactApplicationContext().runOnUiQueueThread(new Runnable() {
            @Override
            public void run() {
                try {
                    promise.resolve(Double.toString(PDFNet.getVersion()));
                } catch (Exception ex) {
                    promise.reject(ex);
                }
            }
        });
    }

    @ReactMethod
    public void getPlatformVersion(final Promise promise) {
        getReactApplicationContext().runOnUiQueueThread(new Runnable() {
            @Override
            public void run() {
                try {
                    promise.resolve("Android " + android.os.Build.VERSION.RELEASE);
                } catch (Exception ex) {
                    promise.reject(ex);
                }
            }
        });
    }

    @ReactMethod
    public void pdfFromOffice(final String docxPath, final @Nullable ReadableMap options, final Promise promise) {
        try {
            PDFDoc doc = new PDFDoc();
            OfficeToPDFOptions conversionOptions = new OfficeToPDFOptions();

            if (options != null) {
                if (options.hasKey("applyPageBreaksToSheet")) {
                    if (!options.isNull("applyPageBreaksToSheet")) {
                        conversionOptions.setApplyPageBreaksToSheet(options.getBoolean("applyPageBreaksToSheet"));
                    }
                }

                if (options.hasKey("displayChangeTracking")) {
                    if (!options.isNull("displayChangeTracking")) {
                        conversionOptions.setDisplayChangeTracking(options.getBoolean("displayChangeTracking"));
                    }
                }

                if (options.hasKey("excelDefaultCellBorderWidth")) {
                    if (!options.isNull("excelDefaultCellBorderWidth")) {
                        conversionOptions.setExcelDefaultCellBorderWidth(options.getDouble("excelDefaultCellBorderWidth"));
                    }
                }

                if (options.hasKey("excelMaxAllowedCellCount")) {
                    if (!options.isNull("excelMaxAllowedCellCount")) {
                        conversionOptions.setExcelMaxAllowedCellCount(options.getInt("excelMaxAllowedCellCount"));
                    }
                }

                if (options.hasKey("locale")) {
                    if (!options.isNull("locale")) {
                        conversionOptions.setLocale(options.getString("locale"));
                    }
                }
            }

            Convert.officeToPdf(doc, docxPath, conversionOptions);
            File resultPdf = File.createTempFile("tmp", ".pdf", getReactApplicationContext().getFilesDir());
            doc.save(resultPdf.getAbsolutePath(), SDFDoc.SaveMode.NO_FLAGS, null);
            promise.resolve(resultPdf.getAbsolutePath());
        } catch (Exception e) {
            promise.reject(e);
        }
    }

    @ReactMethod
    public void pdfFromOfficeTemplate(final String docxPath, final ReadableMap json, final Promise promise) {
        try {
            PDFDoc doc = new PDFDoc();
            OfficeToPDFOptions options = new OfficeToPDFOptions();
            options.setTemplateParamsJson(ReactUtils.convertMapToJson(json).toString());
            Convert.officeToPdf(doc, docxPath, options);
            File resultPdf = File.createTempFile("tmp", ".pdf", getReactApplicationContext().getFilesDir());
            doc.save(resultPdf.getAbsolutePath(), SDFDoc.SaveMode.NO_FLAGS, null);
            promise.resolve(resultPdf.getAbsolutePath());
        } catch (Exception e) {
            promise.reject(e);
        }
    }

    @ReactMethod
    public void exportAsImage(int pageNumber, double dpi, String exportFormat, final String filePath, boolean transparent, final Promise promise) {
        try {
            PDFDoc doc = new PDFDoc(filePath);
            doc.lockRead();
            String imagePath = ReactUtils.exportAsImageHelper(doc, pageNumber, dpi, exportFormat, transparent);
            doc.unlockRead();
            promise.resolve(imagePath);
        } catch (Exception e) {
            promise.reject(e);
        }
    }

    @ReactMethod
    public void clearSavedViewerState(final Promise promise) {
        try {
            RecentFilesManager.getInstance().clearFiles(getReactApplicationContext());
            PdfViewCtrlTabsManager.getInstance().cleanup();
            PdfViewCtrlTabsManager.getInstance().clearAllPdfViewCtrlTabInfo(getReactApplicationContext());
            PdfViewCtrlSettingsManager.setOpenUrlAsyncCache(getReactApplicationContext(), "");
            PdfViewCtrlSettingsManager.setOpenUrlPageStateAsyncCache(getReactApplicationContext(), "");
            promise.resolve(null);
        } catch (Exception e) {
            promise.reject(e);
        }
    }
}