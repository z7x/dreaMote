//
//  AfterEventViewController.m
//  dreaMote
//
//  Created by Moritz Venn on 10.03.08.
//  Copyright 2008-2011 Moritz Venn. All rights reserved.
//

#import "AfterEventViewController.h"

#import "Constants.h"
#import "UITableViewCell+EasyInit.h"

#import "TimerProtocol.h"

@interface AfterEventViewController()
/*!
 @brief done editing
 */
- (void)doneAction:(id)sender;
@end

@implementation AfterEventViewController

/* initialize */
- (id)init
{
	if((self = [super init]))
	{
		self.title = NSLocalizedString(@"After Event", @"Default title of AfterEventViewController");

		if([self respondsToSelector:@selector(modalPresentationStyle)])
		{
			self.modalPresentationStyle = UIModalPresentationFormSheet;
			self.modalTransitionStyle = UIModalTransitionStyleFlipHorizontal;
		}
	}
	return self;
}

/* new AfterEventViewController */
+ (AfterEventViewController *)withAfterEvent: (NSUInteger)afterEvent andAuto: (BOOL)showAuto
{
	AfterEventViewController *afterEventViewController = [[AfterEventViewController alloc] init];
	afterEventViewController.selectedItem = afterEvent;
	afterEventViewController.showAuto = showAuto;

	return [afterEventViewController autorelease];
}

- (NSUInteger)selectedItem
{
	return _selectedItem;
}

- (void)setSelectedItem:(NSUInteger)newSelectedItem
{
	_selectedItem = newSelectedItem;
	[(UITableView *)self.view reloadData];
}

- (BOOL)showAuto
{
	return _showAuto;
}

- (void)setShowAuto:(BOOL)newShowAuto
{
	_showAuto = newShowAuto;
	[(UITableView *)self.view reloadData];
}

- (BOOL)showDefault
{
	return _showDefault;
}

- (void)setShowDefault:(BOOL)newShowDefault
{
	_showDefault = newShowDefault;
	[(UITableView *)self.view reloadData];
}

/* dealloc */
- (void)dealloc
{
	[super dealloc];
}

/* layout */
- (void)loadView
{
	// create and configure the table view
	UITableView *tableView = [[UITableView alloc] initWithFrame:[[UIScreen mainScreen] applicationFrame] style:UITableViewStyleGrouped];	
	tableView.delegate = self;
	tableView.dataSource = self;
	tableView.rowHeight = kUIRowHeight;

	// setup our content view so that it auto-rotates along with the UViewController
	tableView.autoresizesSubviews = YES;
	tableView.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);

	self.view = tableView;
	[tableView release];

	UIBarButtonItem *button = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
																			target:self action:@selector(doneAction:)];
	self.navigationItem.rightBarButtonItem = button;
	[button release];
}

/* finish */
- (void)doneAction:(id)sender
{
	if(IS_IPAD())
		[self.navigationController dismissModalViewControllerAnimated:YES];
	else
		[self.navigationController popViewControllerAnimated: YES];
}

/* rotate with device */
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
	return YES;
}

#pragma mark - UITableView delegates

/* title for section */
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	return nil;
}

/* number of rows */
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	NSInteger rows = kAfterEventMax;
	if(!_showAuto)
		--rows;
	if(_showDefault)
		++rows;
	return rows;
}

/* to determine which UITableViewCell to be used on a given row. */
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	UITableViewCell *cell = [UITableViewCell reusableTableViewCellInView:tableView withIdentifier:kVanilla_ID];

	// we are creating a new cell, setup its attributes
	switch(indexPath.row)
	{
		case kAfterEventNothing:
			TABLEVIEWCELL_TEXT(cell) = NSLocalizedString(@"Nothing", @"After Event");
			break;
		case kAfterEventStandby:
			TABLEVIEWCELL_TEXT(cell) = NSLocalizedString(@"Standby", @"");
			break;
		case kAfterEventDeepstandby:
			TABLEVIEWCELL_TEXT(cell) = NSLocalizedString(@"Deep Standby", @"");
			break;
		case kAfterEventAuto:
			if(_showAuto)
			{
				TABLEVIEWCELL_TEXT(cell) = NSLocalizedString(@"Auto", @"");
				break;
			}
			/* FALL THROUGH */
		case kAfterEventMax:
			TABLEVIEWCELL_TEXT(cell) = NSLocalizedString(@"Default Action", @"Default After Event action (usually auto on enigma2 receivers)");
			break;
		default:
			break;
	}

	if(indexPath.row == _selectedItem)
		cell.accessoryType = UITableViewCellAccessoryCheckmark;
	else
		cell.accessoryType = UITableViewCellAccessoryNone;

	return cell;
}

/* row selected */
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	[tableView deselectRowAtIndexPath: indexPath animated: YES];
	
	UITableViewCell *cell = [tableView cellForRowAtIndexPath: [NSIndexPath indexPathForRow: _selectedItem inSection: 0]];
	cell.accessoryType = UITableViewCellAccessoryNone;
	
	cell = [tableView cellForRowAtIndexPath: indexPath];
	cell.accessoryType = UITableViewCellAccessoryCheckmark;
	
	_selectedItem = indexPath.row;

	if(IS_IPAD())
	{
		[self dismissModalViewControllerAnimated:YES];
	}
}

/* set delegate */
- (void)setDelegate: (id<AfterEventDelegate>) delegate
{
	/*!
	 @note We do not retain the target, this theoretically could be a problem but
	 is not in this case.
	 */
	_delegate = delegate;
}

#pragma mark - UIViewController delegate methods

/* about to disappear */
- (void)viewWillDisappear:(BOOL)animated
{
	if(_delegate != nil)
	{
		[_delegate performSelector:@selector(afterEventSelected:) withObject: [NSNumber numberWithInteger: _selectedItem]];
	}
}

@end