#import "DocumentController.h"

static char* saveDoc(char *current_path, fz_document *doc, BOOL replace)
{
  if (replace) {
    saveDoc(current_path, doc);

    return current_path;
  } else {
    tmp = tmp_path(current_path);
	if (tmp)
	{
		int written = 0;

        try {
			FILE *fin = fopen(current_path, "rb");
			FILE *fout = fopen(tmp, "wb");
			char buf[256];
			size_t n;
			int err = 1;

			if (fin && fout)
			{
				while ((n = fread(buf, 1, sizeof(buf), fin)) > 0)
					fwrite(buf, 1, n, fout);
				err = (ferror(fin) || ferror(fout));
			}

			if (fin)
				fclose(fin);
			if (fout)
				fclose(fout);

            if (!err) {
                saveDoc(tmp, doc);
            }
        } catch() {
            return null;
        }

        return tmp;
    }
}

@implementation DocumentController
{
	BOOL annotationsEnabled;
	BOOL isAnnotatedPdf;
}

- (instancetype) initWithFilename:(NSString*)filename path:(char *)path document:(MuDocRef *)aDoc options:(NSDictionary*)options
{
	self = [super initWithFilename:filename path:path document:aDoc];
	if (!self)
		return nil;

	annotationsEnabled = [[options valueForKey:@"annotationsEnabled"] boolValue];
    isAnnotatedPdf = [[options valueForKey:@"isAnnotatedPdf"] boolValue];
    headerColor = [[options valueForKey:@"headerColor"] stringValue];

	return self;
}

//TODO [self navigationItem] === mainBar?? (headerColor???)

- (void) loadView
{
	[[NSUserDefaults standardUserDefaults] setObject: key forKey: @"OpenDocumentKey"];

	current = (int)[[NSUserDefaults standardUserDefaults] integerForKey: key];
	if (current < 0 || current >= fz_count_pages(ctx, doc))
		current = 0;

	UIView *view = [[UIView alloc] initWithFrame: CGRectZero];
	view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[view setAutoresizesSubviews: YES];
	view.backgroundColor = [UIColor grayColor];

	canvas = [[UIScrollView alloc] initWithFrame: CGRectMake(0,0,GAP,0)];
	canvas.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[canvas setPagingEnabled: YES];
	[canvas setShowsHorizontalScrollIndicator: NO];
	[canvas setShowsVerticalScrollIndicator: NO];
	canvas.delegate = self;

	UITapGestureRecognizer *tapRecog = [[UITapGestureRecognizer alloc] initWithTarget: self action: @selector(onTap:)];
	tapRecog.delegate = self;
	[canvas addGestureRecognizer: tapRecog];
	[tapRecog release];
	// In reflow mode, we need to track pinch gestures on the canvas and pass
	// the scale changes to the subviews.
	UIPinchGestureRecognizer *pinchRecog = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(onPinch:)];
	pinchRecog.delegate = self;
	[canvas addGestureRecognizer:pinchRecog];
	[pinchRecog release];

	scale = 1.0;

	scroll_animating = NO;

	indicator = [[UILabel alloc] initWithFrame: CGRectZero];
	indicator.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
	indicator.text = @"0000 of 9999";
	[indicator sizeToFit];
	indicator.center = CGPointMake(0, INDICATOR_Y);
	indicator.textAlignment = NSTextAlignmentCenter;
	indicator.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent: 0.5];
	indicator.textColor = [UIColor whiteColor];

	[view addSubview: canvas];
	[view addSubview: indicator];

	slider = [[UISlider alloc] initWithFrame: CGRectZero];
	slider.minimumValue = 0;
	slider.maximumValue = fz_count_pages(ctx, doc) - 1;
	[slider addTarget: self action: @selector(onSlide:) forControlEvents: UIControlEventValueChanged];

	if ([UIDevice currentDevice].systemVersion.floatValue < 7.0)
	{
		sliderWrapper = [[UIBarButtonItem alloc] initWithCustomView: slider];

		self.toolbarItems = @[sliderWrapper];
	}

	// Set up the buttons on the navigation and search bar

	fz_outline *outlineRoot = NULL;
	fz_try(ctx)
		outlineRoot = fz_load_outline(ctx, doc);
	fz_catch(ctx)
		outlineRoot = NULL;
	if (outlineRoot)
	{
		//  only show the outline button if there is an outline
		outlineButton = [self newResourceBasedButton:@"ic_list" withAction:@selector(onShowOutline:)];
		fz_drop_outline(ctx, outlineRoot);
	}

	linkButton = [self newResourceBasedButton:@"ic_link" withAction:@selector(onToggleLinks:)];
	cancelButton = [self newResourceBasedButton:@"ic_cancel" withAction:@selector(onCancel:)];
	searchButton = [self newResourceBasedButton:@"ic_magnifying_glass" withAction:@selector(onShowSearch:)];
	prevButton = [self newResourceBasedButton:@"ic_arrow_left" withAction:@selector(onSearchPrev:)];
	nextButton = [self newResourceBasedButton:@"ic_arrow_right" withAction:@selector(onSearchNext:)];
	reflowButton = [self newResourceBasedButton:@"ic_reflow" withAction:@selector(onToggleReflow:)];
	moreButton = [self newResourceBasedButton:@"ic_more" withAction:@selector(onMore:)];

	if (annotationsEnabled)
	    annotButton = [self newResourceBasedButton:@"ic_annotation" withAction:@selector(onAnnot:)];

	shareButton = [self newResourceBasedButton:@"ic_share" withAction:@selector(onShare:)];
	printButton = [self newResourceBasedButton:@"ic_print" withAction:@selector(onPrint:)];
	highlightButton = [self newResourceBasedButton:@"ic_highlight" withAction:@selector(onHighlight:)];
	underlineButton = [self newResourceBasedButton:@"ic_underline" withAction:@selector(onUnderline:)];
	strikeoutButton = [self newResourceBasedButton:@"ic_strike" withAction:@selector(onStrikeout:)];
	inkButton = [self newResourceBasedButton:@"ic_pen" withAction:@selector(onInk:)];
	tickButton = [self newResourceBasedButton:@"ic_check" withAction:@selector(onTick:)];
	deleteButton = [self newResourceBasedButton:@"ic_trash" withAction:@selector(onDelete:)];
	searchBar = [[UISearchBar alloc] initWithFrame: CGRectMake(0,0,50,32)];
	backButton = [self newResourceBasedButton:@"ic_arrow_left" withAction:@selector(onBack:)];
	searchBar.placeholder = @"Search";
	searchBar.delegate = self;

	[prevButton setEnabled: NO];
	[nextButton setEnabled: NO];

	[self addMainMenuButtons];

	// TODO: add activityindicator to search bar

	self.view = view;
	[view release];
}

- (void) showMoreMenu
{
	// NSMutableArray *rightbuttons = [NSMutableArray arrayWithObjects:printButton, shareButton, nil];
	NSMutableArray *rightbuttons = [NSMutableArray arrayWithObjects:printButton, nil];
	if (annotationsEnabled && docRef->interactive)
		[rightbuttons insertObject:annotButton atIndex:0];
	self.navigationItem.rightBarButtonItems = rightbuttons;
	self.navigationItem.leftBarButtonItem = cancelButton;

	barmode = BARMODE_MORE;
}

- (void) shareDocument:(NSString *)path
{
	NSURL *url = [NSURL fileURLWithPath:path];
	UIActivityViewController *cont = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
	cont.popoverPresentationController.barButtonItem = shareButton;
	[self presentViewController:cont animated:YES completion:nil];
	[cont release];
}

- (void) onBack: (id)sender
{
	pdf_document *idoc = pdf_specifics(ctx, doc);
	if (idoc && pdf_has_unsaved_changes(ctx, idoc))
	{
		UIAlertView *saveAlert = [[UIAlertView alloc] initWithTitle:AlertTitle message:CloseAlertMessage delegate:self cancelButtonTitle:@"Discard" otherButtonTitles:@"Save", nil];
		[saveAlert show];
		[saveAlert release];
	}
	else
	{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DocumentControllerDismissed" object:nil userInfo:nil];
        [self.navigationController popViewControllerAnimated:YES];
	}
}

- (void) alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
	if ([CloseAlertMessage isEqualToString:alertView.message])
	{
		if (buttonIndex == 1)
			saveDoc(_filePath.UTF8String, doc, true);

		[alertView dismissWithClickedButtonIndex:buttonIndex animated:YES];

        [[NSNotificationCenter defaultCenter] postNotificationName:@"DocumentControllerDismissed" object:nil userInfo:nil];
        [self.navigationController popViewControllerAnimated:YES];
	}

	if ([ShareAlertMessage isEqualToString:alertView.message])
	{
		[alertView dismissWithClickedButtonIndex:buttonIndex animated:NO];
		if (buttonIndex == 1)
		{
			char* tmp = saveDoc(_filePath.UTF8String, doc, false);

			if (tmp != nil)
			{
                NSString *path = [NSString stringWithUTF8String:tmp];
                [self shareDocument:path];
            }
		}
	}
}

- (void) onTap: (UITapGestureRecognizer*)sender
{
	CGPoint p = [sender locationInView: canvas];
	CGPoint ofs = canvas.contentOffset;
	float x0 = (width - GAP) / 5;
	float x1 = (width - GAP) - x0;
	p.x -= ofs.x;
	p.y -= ofs.y;
	__block BOOL tapHandled = NO;
	for (UIView<MuPageView> *view in canvas.subviews)
	{
		CGPoint pp = [sender locationInView:view];
		if (CGRectContainsPoint(view.bounds, pp))
		{
			MuTapResult *result = [view handleTap:pp];
			__block BOOL hitAnnot = NO;
			[result switchCaseInternal:^(MuTapResultInternalLink *link) {
				[self gotoPage:link.pageNumber animated:NO];
				tapHandled = YES;
			} caseExternal:^(MuTapResultExternalLink *link) {
				[[UIApplication sharedApplication] openURL:[NSURL URLWithString:link.url]];
			} caseRemote:^(MuTapResultRemoteLink *link) {
				// Not currently supported
			} caseWidget:^(MuTapResultWidget *widget) {
				tapHandled = YES;
			} caseAnnotation:^(MuTapResultAnnotation *annot) {
				hitAnnot = YES;
			}];

			switch (barmode)
			{
				case BARMODE_ANNOTATION:
					if (hitAnnot)
						[self deleteModeOn];
					tapHandled = YES;
					break;

				case BARMODE_DELETE:
					if (!hitAnnot)
						[self showAnnotationMenu];
					tapHandled = YES;
					break;

				default:
					if (hitAnnot)
					{
						// Annotation will have been selected, which is wanted
						// only in annotation-editing mode
						[view deselectAnnotation];
					}
					break;
			}

			if (tapHandled)
				break;
		}
	}
	if (tapHandled) {
		// Do nothing further
	} else if (p.x < x0) {
		[self gotoPage: current-1 animated: YES];
	} else if (p.x > x1) {
		[self gotoPage: current+1 animated: YES];
	} else {
		if (self.navigationController.navigationBarHidden)
			[self showNavigationBar];
		else if (barmode == BARMODE_MAIN)
			[self hideNavigationBar];
	}
}

@end
