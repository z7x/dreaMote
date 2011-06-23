//
//  MovieViewController.m
//  dreaMote
//
//  Created by Moritz Venn on 09.03.08.
//  Copyright 2008-2011 Moritz Venn. All rights reserved.
//

#import "MovieViewController.h"

#import "Constants.h"
#import "MovieListController.h"
#import "RemoteConnectorObject.h"
#import "TimerViewController.h"

#import "NSDateFormatter+FuzzyFormatting.h"
#import "NSString+URLEncode.h"
#import "UITableViewCell+EasyInit.h"

#import "CellTextView.h"
#import "DisplayCell.h"

@interface MovieViewController()
- (UITextView *)create_Summary;
- (UIButton *)createButtonForSelector:(SEL)selector withImage:(NSString *)imageName;
@property (nonatomic, retain) UIPopoverController *popoverController;
@end

@interface MovieViewController(IMDb)
- (void)openIMDb:(id)sender;
@end

@interface MovieViewController(Streaming)
- (void)openOPlayer:(id)sender;
- (void)openOPlayerLite:(id)sender;
- (void)openBuzzPlayer:(id)sender;
- (void)openYxplayer:(id)sender;
@end

@implementation MovieViewController

@synthesize movieList, popoverController;

- (id)init
{
	if((self = [super init]))
	{
		self.title = NSLocalizedString(@"Movie", @"Default title of MovieViewController");
		_movie = nil;

		if([self respondsToSelector:@selector(modalPresentationStyle)])
		{
			self.modalPresentationStyle = UIModalPresentationFormSheet;
			self.modalTransitionStyle = UIModalTransitionStyleFlipHorizontal;
		}
	}
	
	return self;
}

+ (MovieViewController *)withMovie: (NSObject<MovieProtocol> *) newMovie
{
	MovieViewController *movieViewController = [[MovieViewController alloc] init];

	movieViewController.movie = newMovie;

	return [movieViewController autorelease];
}

- (void)dealloc
{
	[movieList release];
	[popoverController release];
	[_movie release];
	[_summaryView release];

	[super dealloc];
}

- (NSObject<MovieProtocol> *)movie
{
	return _movie;
}

- (void)setMovie: (NSObject<MovieProtocol> *)newMovie
{
	if(_movie != newMovie)
	{
		[_movie release];
		_movie = [newMovie retain];
	}

	if(newMovie != nil)
	{
		self.title = newMovie.title;

		[_summaryView release];
		_summaryView = [[self create_Summary] retain];
	}
	else
	{
		self.title = NSLocalizedString(@"Movie", @"Default title of MovieViewController");
	}
	
	// Eventually remove popover
	if(self.popoverController != nil) {
        [self.popoverController dismissPopoverAnimated:YES];
    }

	[(UITableView *)self.view reloadData];
	[(UITableView *)self.view
						scrollToRowAtIndexPath: [NSIndexPath indexPathForRow:0 inSection:0]
						atScrollPosition: UITableViewScrollPositionTop
						animated: NO];
}

- (void)loadView
{
	// create and configure the table view
	UITableView *tableView = [[SwipeTableView alloc] initWithFrame:[[UIScreen mainScreen] applicationFrame] style:UITableViewStyleGrouped];
	tableView.delegate = self;
	tableView.dataSource = self;
	tableView.sectionFooterHeight = 1;
	tableView.sectionHeaderHeight = 1;

	// setup our content view so that it auto-rotates along with the UViewController
	tableView.autoresizesSubviews = YES;
	tableView.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);

	self.view = tableView;
	[tableView release];
}

//* Start playback of the movie on the remote box
//* @see #zapTo:
- (void)playAction: (id)sender
{
	NSIndexPath *indexPath = [NSIndexPath indexPathForRow:0 inSection:6];
	[(UITableView *)self.view
						selectRowAtIndexPath: indexPath
						animated: YES
						scrollPosition: UITableViewScrollPositionNone];

	[[RemoteConnectorObject sharedRemoteConnector] playMovie: _movie];

	[(UITableView *)self.view deselectRowAtIndexPath: indexPath animated: YES];
}

- (UITextView *)create_Summary
{
	UITextView *myTextView = [[UITextView alloc] initWithFrame:CGRectZero];
	myTextView.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
	myTextView.textColor = [UIColor blackColor];
	myTextView.font = [UIFont fontWithName:kFontName size:kTextViewFontSize];
	myTextView.editable = NO;

	// We display short description (or title) and extended description (if available)
	// in our textview
	NSMutableString *text;
	if(![[RemoteConnectorObject sharedRemoteConnector] hasFeature: kFeaturesExtendedRecordInfo]
	   || !_movie)
		text = [_movie.title copy];
	else
	{
		text = [[NSMutableString alloc] init];
		if([_movie.sdescription length])
			[text appendString: _movie.sdescription];
		else
			[text appendString: _movie.title];

		if([_movie.edescription length])
		{
			[text appendString: @"\n\n"];
			[text appendString: _movie.edescription];
		}
	}
	myTextView.text = text;

	[text release];

	return [myTextView autorelease];
}

- (NSString *)format_BeginEnd: (NSDate *)dateTime
{
	const NSDateFormatter *format = [[NSDateFormatter alloc] init];
	[format setDateStyle:NSDateFormatterFullStyle];
	[format setTimeStyle:NSDateFormatterShortStyle];
	NSString *dateString = [format fuzzyDate: dateTime];
	[format release];
	return dateString;
}

- (UIButton *)createButtonForSelector:(SEL)selector withImage:(NSString *)imageName
{
	const CGRect frame = CGRectMake(0, 0, kUIRowHeight, kUIRowHeight);
	UIButton *button = [[UIButton alloc] initWithFrame: frame];
	if(imageName)
	{
		UIImage *image = [UIImage imageNamed:imageName];
		[button setImage:image forState:UIControlStateNormal];
	}
	[button addTarget:self action:selector
				forControlEvents:UIControlEventTouchUpInside];

	return [button autorelease];
}

//* Convert the size in bytes of a movie to a human-readable size
//* @param size NSNumber containing size in bytes
- (NSString *)format_size: (NSNumber*)size
{
	float floatSize = [size floatValue];

	if (floatSize < 1023)
		return [NSString stringWithFormat: @"%i bytes", floatSize];
	floatSize /= 1024;

	if (floatSize < 1023)
		return [NSString stringWithFormat: @"%1.1f KB", floatSize];
	floatSize /= 1024;

	if (floatSize < 1023)
		return [NSString stringWithFormat: @"%1.1f MB", floatSize];
	floatSize /= 1024;

	return [NSString stringWithFormat: @"%1.1f GB", floatSize];
}

#pragma mark -
#pragma mark SwipeTableViewDelegate
#pragma mark -
#if IS_FULL()

- (void)tableView:(SwipeTableView *)tableView didSwipeRowAtIndexPath:(NSIndexPath *)indexPath
{
	//if(tableView.lastSwipe & twoFingers)
	{
		NSObject<MovieProtocol> *newMovie = nil;
		if(tableView.lastSwipe & swipeTypeLeft)
			newMovie = [movieList previousMovie];
		else // if(tableView.lastSwipe & swipeTypeRight)
			newMovie = [movieList nextMovie];

		if(newMovie)
			self.movie = newMovie;
		else
		{
			const UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"End of list reached", @"Title of message when trying to select next/previous movie by swiping but end was reached.")
																  message:NSLocalizedString(@"You have reached either the end or the beginning of your movie list.", @"")
																 delegate:nil
														cancelButtonTitle:@"OK"
														otherButtonTitles:nil];
			[alert show];
			[alert release];
		}
	}
}

#endif
#pragma mark - UITableView delegates

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	const UITableViewCell *cell = [tableView cellForRowAtIndexPath: indexPath];
	if([cell respondsToSelector: @selector(view)]
		&& [((DisplayCell *)cell).view respondsToSelector:@selector(sendActionsForControlEvents:)])
	{
		[(UIButton *)((DisplayCell *)cell).view sendActionsForControlEvents: UIControlEventTouchUpInside];
	}
	return nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	// We always have 7 sections, but not all of them have content
	return 7;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	// First section is always present
	if(section == 0)
		return NSLocalizedString(@"Description", @"");

	// Other rows might be displayed if we have extended record description
	if([[RemoteConnectorObject sharedRemoteConnector] hasFeature: kFeaturesExtendedRecordInfo])
	{
		switch(section)
		{
			case 1:
				if([_movie.sname length])
					return NSLocalizedString(@"Service", @"");
				break;
			case 2:
				return NSLocalizedString(@"Size", @"");
			case 3:
				return NSLocalizedString(@"Tags", @"");
			case 4:
				return NSLocalizedString(@"Begin", @"");
			case 5:
				if([_movie.length integerValue] != -1)
					return NSLocalizedString(@"End", @"");
				/* FALL THROUGH */
			default:
				return nil;
		}
	}
	
	return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	NSUInteger count = 0;

	if(section == 6)
	{
		NSUInteger rows = 1;
		if([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"imdb:///"]])
			++rows;

		if([[RemoteConnectorObject sharedRemoteConnector] hasFeature:kFeaturesStreaming])
		{
			if([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"oplayer:///"]])
				++rows;
			if([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"oplayerlite:///"]])
				++rows;
			if([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"buzzplayer:///"]])
				++rows;
			if([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"yxp:///"]])
				++rows;
		}
		return rows;
	}

	if([[RemoteConnectorObject sharedRemoteConnector] hasFeature: kFeaturesExtendedRecordInfo])
	{
		/*
		 * If we have extended record descriptions we show most of the rows (unless movie length
		 * is unknown in this case its hidden) and the only section which can have more than one
		 * row is section 3 (movie tags).
		 */
		switch(section)
		{
			case 1:
				if(![_movie.sname length])
					return 0;
				return 1;
			case 3:
				count = [_movie.tags count];
				if(!count)
					return 1;
				return count;
			case 5:
				if([_movie.length integerValue] != -1)
					return 1;
				return 0;
			default:
				return 1;
		}
	}
	else
	{
		// Only section 0 and 6 are displayed when we only have basic information.
		switch(section)
		{
			case 0:
				return 1;
			case 6:
				return 1;
			default:
				return 0;
		}
	}

	return 0;
}

// as some rows are hidden we want to hide the gap created by empty sections by
// resizing the header fields.
//
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
	if(section == 0)
		return 34;

	if([[RemoteConnectorObject sharedRemoteConnector] hasFeature: kFeaturesExtendedRecordInfo])
	{
		switch(section)
		{
			case 1:
				if(![_movie.sname length])
					return 0;
				break;
			case 5:
				if([_movie.length integerValue] == -1)
					return 0;
				break;
			default: break;
		}
		return 34;
	}

	return 0;
}

// determine the adjustable height of a row. these are determined by the sections and if a
// section is set to be hidden the row size is reduced to 0.
//
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	const NSInteger section = indexPath.section;
	if(section == 0)
		return kTextViewHeight;
	else if(section == 6)
		return kUIRowHeight;

	if([[RemoteConnectorObject sharedRemoteConnector] hasFeature: kFeaturesExtendedRecordInfo])
	{
		switch(section)
		{
			case 1:
				if(![_movie.sname length])
					return 0;
				break;
			case 5:
				if([_movie.length integerValue] == -1)
					return 0;
				break;
			default: break;
		}
		return kUIRowHeight;
	}

	return 0;
}

// utility routine leveraged by 'cellForRowAtIndexPath' to determine which UITableViewCell to be used on a given section.
//
- (UITableViewCell *)obtainTableCellForSection:(UITableView *)tableView: (NSInteger)section
{
	UITableViewCell *cell = nil;

	switch (section) {
		case 0:
			cell = [CellTextView reusableTableViewCellInView:tableView withIdentifier:kCellTextView_ID];
			break;
		case 1:
		case 2:
		case 3:
		case 4:
		case 5:
			cell = [UITableViewCell reusableTableViewCellInView:tableView withIdentifier:kVanilla_ID];

			TABLEVIEWCELL_ALIGN(cell) = UITextAlignmentCenter;
			TABLEVIEWCELL_COLOR(cell) = [UIColor blackColor];
			TABLEVIEWCELL_FONT(cell) = [UIFont systemFontOfSize:kTextViewFontSize];
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			cell.textLabel.adjustsFontSizeToFitWidth = YES;
			cell.indentationLevel = 0;
			break;
		case 6:
			cell = [DisplayCell reusableTableViewCellInView:tableView withIdentifier:kDisplayCell_ID];
			/* FALL THROUGH */
		default:
			break;
	}

	return cell;
}

// to determine which UITableViewCell to be used on a given row.
//
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	const NSInteger section = indexPath.section;
	UITableViewCell *sourceCell = [self obtainTableCellForSection: tableView: section];

	// we are creating a new cell, setup its attributes
	switch (section) {
		case 0:
			((CellTextView *)sourceCell).view = _summaryView;
			_summaryView.backgroundColor = sourceCell.backgroundColor;
			break;
		case 1:
			TABLEVIEWCELL_TEXT(sourceCell) = _movie.sname;
			break;
		case 2:
			if([_movie.size integerValue] != -1)
				TABLEVIEWCELL_TEXT(sourceCell) = [self format_size: _movie.size];
			else
				TABLEVIEWCELL_TEXT(sourceCell) = NSLocalizedString(@"N/A", @"");
			break;
		case 3:
			if(![_movie.tags count])
				TABLEVIEWCELL_TEXT(sourceCell) = NSLocalizedString(@"None", @"");
			else
				TABLEVIEWCELL_TEXT(sourceCell) = [_movie.tags objectAtIndex: indexPath.row];
			break;
		case 4:
			TABLEVIEWCELL_TEXT(sourceCell) = [self format_BeginEnd: _movie.time];
			break;
		case 5:
			TABLEVIEWCELL_TEXT(sourceCell) = [self format_BeginEnd: [_movie.time addTimeInterval: (NSTimeInterval)[_movie.length integerValue]]];
			break;
		case 6:
		{
			NSInteger row = indexPath.row;
			sourceCell.selectionStyle = UITableViewCellSelectionStyleBlue;

			if(![[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"imdb:///"]] && row > 0)
				++row;

			if([[RemoteConnectorObject sharedRemoteConnector] hasFeature:kFeaturesStreaming])
			{
				if(![[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"oplayer:///"]] && row > 1)
					++row;
				if(![[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"oplayerlite:///"]] && row > 2)
					++row;
				if(![[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"buzzplayer:///"]] && row > 3)
					++row;
				//if(![[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"yxp:///"]] && row > 4)
				//	++row;
			}
			else if(row > 1)
			{
				row += 2;
			}
			switch(row)
			{
				default:
				case 0:
					((DisplayCell *)sourceCell).nameLabel.text = NSLocalizedString(@"Play", @"");
					((DisplayCell *)sourceCell).view = [self createButtonForSelector:@selector(playAction:) withImage:@"media-playback-start.png"];
					break;
				case 1:
					((DisplayCell *)sourceCell).nameLabel.text = @"IMDb";
					((DisplayCell *)sourceCell).view = [self createButtonForSelector:@selector(openIMDb:) withImage:nil];
					break;
				case 2:
					((DisplayCell *)sourceCell).nameLabel.text = @"OPlayer";
					((DisplayCell *)sourceCell).view = [self createButtonForSelector:@selector(openOPlayer:) withImage:nil];
					break;
				case 3:
					((DisplayCell *)sourceCell).nameLabel.text = @"OPlayer Lite";
					((DisplayCell *)sourceCell).view = [self createButtonForSelector:@selector(openOPlayerLite:) withImage:nil];
					break;
				case 4:
					((DisplayCell *)sourceCell).nameLabel.text = @"BUZZ Player";
					((DisplayCell *)sourceCell).view = [self createButtonForSelector:@selector(openBuzzPlayer:) withImage:nil];
					break;
				case 5:
					((DisplayCell *)sourceCell).nameLabel.text = @"yxplayer";
					((DisplayCell *)sourceCell).view = [self createButtonForSelector:@selector(openYxplayer:) withImage:nil];
					break;
			}
		}
		default:
			break;
	}
	
	return sourceCell;
}

/* rotate with device */
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
	return YES;
}

#pragma mark -
#pragma mark Split view support
#pragma mark -

- (void)splitViewController:(MGSplitViewController*)svc willHideViewController:(UIViewController *)aViewController withBarButtonItem:(UIBarButtonItem*)barButtonItem forPopoverController: (UIPopoverController*)pc
{
	barButtonItem.title = aViewController.title;
	self.navigationItem.leftBarButtonItem = barButtonItem;
	pc.contentViewController = aViewController;
	self.popoverController = pc;
}

// Called when the view is shown again in the split view, invalidating the button and popover controller.
- (void)splitViewController:(MGSplitViewController*)svc willShowViewController:(UIViewController *)aViewController invalidatingBarButtonItem:(UIBarButtonItem *)barButtonItem
{
	self.navigationItem.leftBarButtonItem = nil;
	self.popoverController = nil;
}

#pragma mark IMDb

- (void)openIMDb:(id)sender
{
	NSString *encoded = [_movie.title urlencode];
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"imdb:///find?q=%@", encoded]];

	[[UIApplication sharedApplication] openURL:url];
}

#pragma mark Streaming

- (void)openStreamWithBase:(NSString *)baseString
{
	NSURL *streamingURL = [[RemoteConnectorObject sharedRemoteConnector] getStreamURLForMovie:_movie];
	if(!streamingURL)
	{
		// Alert user
		const UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Error", @"")
															  message:NSLocalizedString(@"Unable to generate stream URL.", @"Failed to retrieve or generate URL of remote stream")
															 delegate:nil
													cancelButtonTitle:@"OK"
													otherButtonTitles:nil];
		[alert show];
		[alert release];
	}
	else
	{
		NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", baseString, [streamingURL absoluteURL]]];
		[[UIApplication sharedApplication] openURL:url];
	}
}

- (void)openOPlayer:(id)sender
{
	[self openStreamWithBase:@"oplayer://"];
}

- (void)openOPlayerLite:(id)sender
{
	[self openStreamWithBase:@"oplayerlite://"];
}

- (void)openBuzzPlayer:(id)sender
{
	[self openStreamWithBase:@"buzzplayer://"];
}

- (void)openYxplayer:(id)sender
{
	[self openStreamWithBase:@"yxp://"];
}

@end