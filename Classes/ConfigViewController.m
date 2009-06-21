//
//  ConfigViewController.m
//  dreaMote
//
//  Created by Moritz Venn on 10.03.08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "ConfigViewController.h"

#import "RemoteConnector.h"
#import "RemoteConnectorObject.h"
#import "ConnectorViewController.h"
#import "Constants.h"

#import "DisplayCell.h"

@interface ConfigViewController()
- (void)setViewMovedUp:(BOOL)movedUp;
@end

@implementation ConfigViewController

@synthesize connection = _connection;
@synthesize connectionIndex = _connectionIndex;
@synthesize makeDefaultButton = _makeDefaultButton;
@synthesize connectButton = _connectButton;

// the amount of vertical shift upwards keep the text field in view as the keyboard appears
#define kOFFSET_FOR_KEYBOARD					150.0

// the duration of the animation for the view shift
#define kVerticalOffsetAnimationDuration		0.30

- (id)init
{
	if (self = [super init])
	{
		self.title = NSLocalizedString(@"Configuration", @"Default title of ConfigViewController");
		_connectorCell = nil;
	}
	return self;
}

+ (ConfigViewController *)withConnection: (NSMutableDictionary *)newConnection: (NSInteger)atIndex;
{
	ConfigViewController *configViewController = [[ConfigViewController alloc] init];
	configViewController.connection = newConnection;
	configViewController.connectionIndex = atIndex;

	return configViewController;
}

+ (ConfigViewController *)newConnection
{
	ConfigViewController *configViewController = [[ConfigViewController alloc] init];
	configViewController.connection = [NSMutableDictionary dictionaryWithObjectsAndKeys:
																@"", kRemoteHost,
																@"", kRemoteName,
																@"", kUsername,
																@"", kPassword,
																[NSNumber numberWithInteger:
																	kEnigma2Connector], kConnector,
																nil];
	configViewController.connectionIndex = -1;

	return configViewController;
}

- (void)dealloc
{
	[_remoteNameTextField release];
	[_remoteAddressTextField release];
	[_remotePortTextField release];
	[_usernameTextField release];
	[_passwordTextField release];
	[_makeDefaultButton release];
	[_connectButton release];
	[_singleBouquetSwitch release];

	[super dealloc];
}

- (UITextField *)create_TextField
{
	UITextField *returnTextField = [[UITextField alloc] initWithFrame:CGRectZero];

	returnTextField.leftView = nil;
	returnTextField.leftViewMode = UITextFieldViewModeNever;
	returnTextField.borderStyle = UITextBorderStyleRoundedRect;
    returnTextField.textColor = [UIColor blackColor];
	returnTextField.font = [UIFont systemFontOfSize:17.0];
    returnTextField.backgroundColor = [UIColor whiteColor];
	// no auto correction support
	returnTextField.autocorrectionType = UITextAutocorrectionTypeNo;

	returnTextField.keyboardType = UIKeyboardTypeDefault;
	returnTextField.returnKeyType = UIReturnKeyDone;

	// has a clear 'x' button to the right
	returnTextField.clearButtonMode = UITextFieldViewModeWhileEditing;

	return returnTextField;
}

- (UIButton *)create_DefaultButton
{
	CGRect frame = CGRectMake(0.0, 0.0, kUIRowHeight, kUIRowHeight);
	UIButton *button = [[UIButton alloc] initWithFrame: frame];
	UIImage *image = [UIImage imageNamed:@"emblem-favorite.png"];
	[button setImage:image forState:UIControlStateNormal];
	[button addTarget:self action:@selector(makeDefault:)
				forControlEvents:UIControlEventTouchUpInside];

	return [button autorelease];
}

- (UIButton *)create_ConnectButton
{
	CGRect frame = CGRectMake(0.0, 0.0, kUIRowHeight, kUIRowHeight);
	UIButton *button = [[UIButton alloc] initWithFrame: frame];
	UIImage *image = [UIImage imageNamed:@"network-wired.png"];
	[button setImage:image forState:UIControlStateNormal];
	[button addTarget:self action:@selector(doConnect:)
				forControlEvents:UIControlEventTouchUpInside];

	return [button autorelease];
}

- (void)loadView
{
	self.navigationItem.rightBarButtonItem = self.editButtonItem;

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

	// Remote Name
	NSString *remoteName = [_connection objectForKey: kRemoteName];
	if(remoteName == nil) // Work around unset property
		remoteName = @"";
	_remoteNameTextField = [[self create_TextField] retain];
	_remoteNameTextField.placeholder = NSLocalizedString(@"<name>", @"");
	_remoteNameTextField.text = [remoteName copy];

	// Remote Address
	_remoteAddressTextField = [[self create_TextField] retain];
	_remoteAddressTextField.placeholder = NSLocalizedString(@"<remote address>", @"");
	_remoteAddressTextField.text = [[_connection objectForKey: kRemoteHost] copy];
	_remoteAddressTextField.keyboardType = UIKeyboardTypeURL;

	// Remote Port
	NSNumber *port = [_connection objectForKey: kPort];
	_remotePortTextField = [[self create_TextField] retain];
	_remotePortTextField.placeholder = NSLocalizedString(@"<remote port>", @"");
	_remotePortTextField.text = [port integerValue] ? [port stringValue] : nil;
	_remotePortTextField.keyboardType = UIKeyboardTypeNumbersAndPunctuation; // XXX: we lack a better one :-)

	// Username
	_usernameTextField = [[self create_TextField] retain];
	_usernameTextField.placeholder = NSLocalizedString(@"<remote username>", @"");
	_usernameTextField.text = [[_connection objectForKey: kUsername] copy];

	// Password
	_passwordTextField = [[self create_TextField] retain];
	_passwordTextField.placeholder = NSLocalizedString(@"<remote password>", @"");
	_passwordTextField.text = [[_connection objectForKey: kPassword] copy];
	_passwordTextField.secureTextEntry = YES;

	// Connector
	_connector = [[_connection objectForKey: kConnector] integerValue];

	// Connect Button
	self.connectButton = [self create_ConnectButton];
	_connectButton.enabled = YES;
	
	// "Make Default" Button
	self.makeDefaultButton = [self create_DefaultButton];
	_makeDefaultButton.enabled = YES;

	// Single bouquet switch
	_singleBouquetSwitch = [[UISwitch alloc] initWithFrame: CGRectMake(0, 0, kSwitchButtonWidth, kSwitchButtonHeight)];
	_singleBouquetSwitch.on = [[_connection objectForKey: kSingleBouquet] boolValue];

	// in case the parent view draws with a custom color or gradient, use a transparent color
	_singleBouquetSwitch.backgroundColor = [UIColor clearColor];

	[self setEditing: (_connectionIndex == -1) animated: NO];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated;
{
	[super setEditing: editing animated: animated];

	/*_makeDefaultButton.enabled = editing;
	_connectButton.enabled = editing;*/

	if(!editing)
	{
		[self.navigationItem setLeftBarButtonItem: nil animated: YES];

		[_remoteNameCell stopEditing];
		[_remoteAddressCell stopEditing];
		[_remotePortCell stopEditing];
		[_usernameCell stopEditing];
		[_passwordCell stopEditing];
		_singleBouquetSwitch.enabled = NO;

		if(_shouldSave)
		{
			[_connection setObject: _remoteNameTextField.text forKey: kRemoteName];
			[_connection setObject: _remoteAddressTextField.text forKey: kRemoteHost];
			[_connection setObject: [NSNumber numberWithInteger: [_remotePortTextField.text integerValue]] forKey: kPort];
			[_connection setObject: _usernameTextField.text forKey: kUsername];
			[_connection setObject: _passwordTextField.text forKey: kPassword];
			[_connection setObject: [NSNumber numberWithInteger: _connector] forKey: kConnector];
			[_connection setObject: _singleBouquetSwitch.on ? @"YES" : @"NO" forKey: kSingleBouquet];

			NSMutableArray *connections = [RemoteConnectorObject getConnections];
			if(_connectionIndex == -1)
			{
				[(UITableView *)self.view beginUpdates];
				_connectionIndex = [connections count];
				[connections addObject: _connection];
				// XXX: ugly!
				if(_connectionIndex != [[NSUserDefaults standardUserDefaults] integerForKey: kActiveConnection] || _connectionIndex != [RemoteConnectorObject getConnectedId])
					[(UITableView *)self.view insertSections: [NSIndexSet indexSetWithIndex: 3]
											withRowAnimation: UITableViewRowAnimationFade];
				[(UITableView *)self.view endUpdates];
			}
			else
			{
				[connections replaceObjectAtIndex: _connectionIndex withObject: _connection];

				// Reconnect because changes won't be applied otherwise
				if(_connectionIndex == [RemoteConnectorObject getConnectedId])
					[RemoteConnectorObject connectTo: _connectionIndex];
			}
		}

		if(_connectorCell)
			_connectorCell.accessoryType = UITableViewCellAccessoryNone;
	}
	else
	{
		_shouldSave = YES;
		_singleBouquetSwitch.enabled = YES;
		UIBarButtonItem *cancelButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem: UIBarButtonSystemItemCancel target: self action: @selector(cancelEdit:)];
		[self.navigationItem setLeftBarButtonItem: cancelButtonItem animated: YES];
		[cancelButtonItem release];

		if(_connectorCell)
			_connectorCell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	}
}

- (void)cancelEdit: (id)sender
{
	_shouldSave = NO;
	[self setEditing: NO animated: YES];
	[self.navigationController popViewControllerAnimated: YES];
}

- (void)makeDefault: (id)sender
{
	NSUserDefaults *stdDefaults = [NSUserDefaults standardUserDefaults];
	NSNumber *activeConnection = [NSNumber numberWithInteger: _connectionIndex];

	[(UITableView *)self.view beginUpdates];
	[stdDefaults setObject: activeConnection forKey: kActiveConnection];
	[RemoteConnectorObject connectTo: _connectionIndex];

	[(UITableView *)self.view deleteSections: [NSIndexSet indexSetWithIndex: 3]
								withRowAnimation: UITableViewRowAnimationFade];
	[(UITableView *)self.view endUpdates];
}

- (void)doConnect: (id)sender
{
	NSUserDefaults *stdDefaults = [NSUserDefaults standardUserDefaults];

	[(UITableView *)self.view beginUpdates];
	[RemoteConnectorObject connectTo: _connectionIndex];

	if(_connectionIndex == [stdDefaults integerForKey: kActiveConnection])
		[(UITableView *)self.view deleteSections: [NSIndexSet indexSetWithIndex: 3]
									withRowAnimation: UITableViewRowAnimationFade];
	else
		[(UITableView *)self.view
				deleteRowsAtIndexPaths: [NSArray arrayWithObject:
											[NSIndexPath indexPathForRow:0 inSection:3]]
				withRowAnimation: UITableViewRowAnimationFade];
	[(UITableView *)self.view endUpdates];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
	// Return YES for supported orientations
	return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (void)connectorSelected: (NSNumber*) newConnector
{
	if(newConnector == nil)
		return;

	NSInteger oldConnector = _connector;
	_connector = [newConnector integerValue];

	if(_connector == kInvalidConnector)
	{
		((UITableView *)self.view).userInteractionEnabled = NO;

		NSDictionary *tempConnection = [NSDictionary dictionaryWithObjectsAndKeys:
								_remoteAddressTextField.text, kRemoteHost,
								_remotePortTextField.text, kPort,
								_usernameTextField.text, kUsername,
								_passwordTextField.text, kPassword,
								nil];

		_connector = [RemoteConnectorObject autodetectConnector: tempConnection];
		if(_connector == kInvalidConnector)
		{
			UIAlertView *notification = [[UIAlertView alloc]
								initWithTitle:NSLocalizedString(@"Error", @"")
								message:NSLocalizedString(@"Could not determine remote box type.", @"")
								delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
			[notification show];
			[notification release];

			_connector = oldConnector;
		}

		((UITableView *)self.view).userInteractionEnabled = YES;
	}

	if(_connector == kEnigma1Connector)
		_connectorCell.text = NSLocalizedString(@"Enigma", @"");
	else if(_connector == kEnigma2Connector)
		_connectorCell.text = NSLocalizedString(@"Enigma 2", @"");
	else if(_connector == kNeutrinoConnector)
		_connectorCell.text = NSLocalizedString(@"Neutrino", @"");
	else if(_connector == kSVDRPConnector)
		_connectorCell.text = NSLocalizedString(@"SVDRP", @"");
	else
		_connectorCell.text = @"???";

	[(UITableView *)self.view reloadData];
}

#pragma mark - UITableView delegates

// if you want the entire table to just be re-orderable then just return UITableViewCellEditingStyleNone
//
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
	return UITableViewCellEditingStyleNone;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	if(	_connectionIndex == -1
		|| (_connectionIndex == [[NSUserDefaults standardUserDefaults] integerForKey: kActiveConnection] && _connectionIndex == [RemoteConnectorObject getConnectedId]))
		return 3;
	return 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	switch(section)
	{
		case 0:
			return NSLocalizedString(@"Remote Host", @"");
		case 1:
			return NSLocalizedString(@"Credential", @"");
		case 2:
			return NSLocalizedString(@"Remote Box Type", @"");
		case 3:
		default:
			return nil;
	}
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	switch(section)
	{
		case 0:
			return 3;
		case 1:
			return 2;
		case 2:
			// XXX: HAAAAAAACK - but I really wanted this feature :P
			if(_connector == kEnigma2Connector)
				return 2;
			return 1;
		case 3:
			if(_connectionIndex == [[NSUserDefaults standardUserDefaults] integerForKey: kActiveConnection]
			   || _connectionIndex == [RemoteConnectorObject getConnectedId])
				return 1;
			return 2;
	}
	return 0;
}

// to determine which UITableViewCell to be used on a given row.
//
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	static NSString *kVanilla_ID = @"Vanilla_ID";

	NSInteger section = indexPath.section;
	NSInteger row = indexPath.row;
	UITableViewCell *sourceCell = nil;

	// we are creating a new cell, setup its attributes
	switch(section)
	{
		case 0:
			sourceCell = [tableView dequeueReusableCellWithIdentifier: kCellTextField_ID];
			if(sourceCell == nil)
				sourceCell = [[[CellTextField alloc] initWithFrame: CGRectZero reuseIdentifier: kCellTextField_ID] autorelease];
			((CellTextField *)sourceCell).delegate = self; // so we can detect when cell editing starts

			switch(row)
			{
				case 0:
					((CellTextField *)sourceCell).view = _remoteNameTextField;
					_remoteNameCell = (CellTextField *)sourceCell;
					break;
				case 1:
					((CellTextField *)sourceCell).view = _remoteAddressTextField;
					_remoteAddressCell = (CellTextField *)sourceCell;
					break;
				case 2:
					((CellTextField *)sourceCell).view = _remotePortTextField;
					_remotePortCell = (CellTextField *)sourceCell;
					break;
				default:
					break;
			}
			break;
		case 1:
			sourceCell = [tableView dequeueReusableCellWithIdentifier: kCellTextField_ID];
			if(sourceCell == nil)
				sourceCell = [[[CellTextField alloc] initWithFrame: CGRectZero reuseIdentifier: kCellTextField_ID] autorelease];
			((CellTextField *)sourceCell).delegate = self; // so we can detect when cell editing starts

			switch(row)
			{
				case 0:
					((CellTextField *)sourceCell).view = _usernameTextField;
					_usernameCell = (CellTextField *)sourceCell;
					break;
				case 1:
					((CellTextField *)sourceCell).view = _passwordTextField;
					_passwordCell = (CellTextField *)sourceCell;
					break;
				default:
					break;
			}
			break;
		case 2:
			row = indexPath.row;
			switch(row)
			{
				case 0:
					sourceCell = [tableView dequeueReusableCellWithIdentifier: kVanilla_ID];
					if (sourceCell == nil) 
						sourceCell = [[[UITableViewCell alloc] initWithFrame: CGRectZero reuseIdentifier: kVanilla_ID] autorelease];
					
					if(self.editing)
						sourceCell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
					
					if(_connector == kEnigma1Connector)
						sourceCell.text = NSLocalizedString(@"Enigma", @"");
					else if(_connector == kEnigma2Connector)
						sourceCell.text = NSLocalizedString(@"Enigma 2", @"");
					else if(_connector == kNeutrinoConnector)
						sourceCell.text = NSLocalizedString(@"Neutrino", @"");
					else if(_connector == kSVDRPConnector)
						sourceCell.text = NSLocalizedString(@"SVDRP", @"");
					else
						sourceCell.text = @"???";
					
					_connectorCell = sourceCell;
					break;
				case 1:
					sourceCell = [tableView dequeueReusableCellWithIdentifier: kDisplayCell_ID];
					if(sourceCell == nil)
						sourceCell = [[[DisplayCell alloc] initWithFrame:CGRectZero reuseIdentifier:kDisplayCell_ID] autorelease];

					((DisplayCell *)sourceCell).nameLabel.text = NSLocalizedString(@"Single Bouquet", @"");
					((DisplayCell *)sourceCell).view = _singleBouquetSwitch;
					break;
			}
			break;
		case 3:
			sourceCell = [tableView dequeueReusableCellWithIdentifier: kDisplayCell_ID];
			if(sourceCell == nil)
				sourceCell = [[[DisplayCell alloc] initWithFrame:CGRectZero reuseIdentifier:kDisplayCell_ID] autorelease];

			if(_connectionIndex == [RemoteConnectorObject getConnectedId])
				row++;

			switch(row)
			{
				case 0:
					((DisplayCell *)sourceCell).nameLabel.text = NSLocalizedString(@"Connect", @"");
					((DisplayCell *)sourceCell).view = _connectButton;
					break;
				case 1:
					((DisplayCell *)sourceCell).nameLabel.text = NSLocalizedString(@"Make Default", @"");
					((DisplayCell *)sourceCell).view = _makeDefaultButton;
					break;
				default:
					break;
			}
			break;
		default:
			break;
	}

	return sourceCell;
}

- (NSIndexPath *)tableView:(UITableView *)tv willSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	NSInteger row = indexPath.row;
	if(self.editing && indexPath.section == 2 && row == 0)
	{
		ConnectorViewController *targetViewController = [ConnectorViewController withConnector: _connector];
		[targetViewController setTarget: self action: @selector(connectorSelected:)];
		[self.navigationController pushViewController: targetViewController animated: YES];
		[targetViewController release];
	}
	else if(indexPath.section == 3)
	{
		if(_connectionIndex == [RemoteConnectorObject getConnectedId])
			row++;

		if(row == 0)
			[self doConnect: nil];
		else
			[self makeDefault: nil];
	}

	// We don't want any actual response :-)
    return nil;
}

#pragma mark -
#pragma mark <EditableTableViewCellDelegate> Methods and editing management

- (BOOL)cellShouldBeginEditing:(EditableTableViewCell *)cell
{
	// notify other cells to end editing
	if([cell isEqual: _remoteNameCell])
	{
		[_remoteAddressCell stopEditing];
		[_remotePortCell stopEditing];
		[_usernameCell stopEditing];
		[_passwordCell stopEditing];
	}
	else if([cell isEqual: _remotePortCell])
	{
		[_remoteNameCell stopEditing];
		[_remoteAddressCell stopEditing];
		[_usernameCell stopEditing];
		[_passwordCell stopEditing];
	}
	else if([cell isEqual: _remoteAddressCell])
	{
		[_remoteNameCell stopEditing];
		[_remotePortCell stopEditing];
		[_usernameCell stopEditing];
		[_passwordCell stopEditing];
	}
	else
		[_remoteAddressCell stopEditing];

	// XXX: _usernameCell & _passwordCell will track this themselves

	return self.editing;
}

- (void)cellDidEndEditing:(EditableTableViewCell *)cell
{
	if(([cell isEqual: _usernameCell] && ! _passwordCell.isInlineEditing)
		|| ([cell isEqual: _passwordCell] && !_usernameCell.isInlineEditing))
	{
        // Restore the position of the main view if it was animated to make room for the keyboard.
        if  (self.view.frame.origin.y < 0)
		{
            [self setViewMovedUp:NO];
        }
    }
}

// Animate the entire view up or down, to prevent the keyboard from covering the text field.
- (void)setViewMovedUp:(BOOL)movedUp
{
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration: kVerticalOffsetAnimationDuration];

    // Make changes to the view's frame inside the animation block. They will be animated instead
    // of taking place immediately.
    CGRect rect = self.view.frame;
    if (movedUp)
	{
        // If moving up, not only decrease the origin but increase the height so the view 
        // covers the entire screen behind the keyboard.
        rect.origin.y -= kOFFSET_FOR_KEYBOARD;
        rect.size.height += kOFFSET_FOR_KEYBOARD;
    }
	else
	{
        // If moving down, not only increase the origin but decrease the height.
        rect.origin.y += kOFFSET_FOR_KEYBOARD;
        rect.size.height -= kOFFSET_FOR_KEYBOARD;
    }
    self.view.frame = rect;

    [UIView commitAnimations];
}

- (void)keyboardWillShow:(NSNotification *)notif
{
	// The keyboard will be shown. If the user is editing the username or password, adjust the
	// display so that the field will not be covered by the keyboard.
	if(_usernameCell.isInlineEditing || _passwordCell.isInlineEditing)
	{
		if(self.view.frame.origin.y >= 0)
			[self setViewMovedUp:YES];
	}
	else if(self.view.frame.origin.y < 0)
		[self setViewMovedUp:NO];
}

#pragma mark - UIViewController delegate methods

- (void)viewWillAppear:(BOOL)animated
{
    // watch the keyboard so we can adjust the user interface if necessary.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) 
												name:UIKeyboardWillShowNotification
												object:self.view.window];

	[super viewWillAppear: animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
    // unregister for keyboard notifications while not visible.
    [[NSNotificationCenter defaultCenter] removeObserver:self
												name:UIKeyboardWillShowNotification
												object:nil]; 

	[super viewWillDisappear: animated];
}

@end
