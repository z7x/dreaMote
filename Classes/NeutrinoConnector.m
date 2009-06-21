//
//  NeutrinoConnector.m
//  dreaMote
//
//  Created by Moritz Venn on 15.10.08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "NeutrinoConnector.h"

#import "CXMLElement.h"

#import "Objects/Neutrino/Bouquet.h"
#import "Objects/Generic/Service.h"
#import "Objects/Generic/Volume.h"
#import "Objects/Generic/Timer.h"

#import "XMLReader/BaseXMLReader.h"
#import "XMLReader/Neutrino/EventXMLReader.h"

#import "NeutrinoRCEmulatorController.h"

// Services are 'lightweight'
#define MAX_SERVICES 2048

enum neutrinoMessageTypes {
	kNeutrinoMessageTypeNormal = 0,
	kNeutrinoMessageTypeConfirmed = 1,
	kNeutrinoMessageTypeMax = 2,
};

@implementation NeutrinoConnector

- (const BOOL)hasFeature: (enum connectorFeatures)feature
{
	// Screenshots do not work yet... :-/
	return
		(feature == kFeaturesBouquets) ||
		(feature == kFeaturesConstantTimerId) ||
		(feature == kFeaturesMessageType);
}

- (NSInteger)getMaxVolume
{
	return 100;
}

- (id)initWithAddress: (NSString *)address andUsername: (NSString *)inUsername andPassword: (NSString *)inPassword andPort: (NSInteger)inPort
{
	if(self = [super init])
	{
		// Protect from unexpected input and assume a full URL if address starts with http
		if([address rangeOfString: @"http"].location == 0)
		{
			_baseAddress = [NSURL URLWithString: address];
		}
		else
		{
			NSString *remoteAddress = nil;
			if([inUsername isEqualToString: @""])
				remoteAddress = [NSString stringWithFormat: @"http://%@", address];
			else
				remoteAddress = [NSString stringWithFormat: @"http://%@:%@@%@", inUsername,
								 inPassword, address];
			if(inPort > 0)
				remoteAddress = [remoteAddress stringByAppendingFormat: @":%d", inPort];
			
			_baseAddress = [NSURL URLWithString: remoteAddress];
		}
		[_baseAddress retain];
	}
	return self;
}

- (void)dealloc
{
	[_baseAddress release];
	[_cachedBouquetsXML release];

	[super dealloc];
}

+ (NSObject <RemoteConnector>*)createClassWithAddress:(NSString *) address andUsername: (NSString *)inUsername andPassword: (NSString *)inPassword andPort: (NSInteger)inPort
{
	return (NSObject <RemoteConnector>*)[[NeutrinoConnector alloc] initWithAddress: address andUsername: inUsername andPassword: inPassword andPort: inPort];
}

- (BOOL)isReachable
{
	// Generate URI
	NSURL *myURI = [NSURL URLWithString:@"/control/info"  relativeToURL:_baseAddress];

	[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;

	NSHTTPURLResponse *response;
	NSURLRequest *request = [NSURLRequest requestWithURL: myURI
											 cachePolicy: NSURLRequestReloadIgnoringCacheData timeoutInterval: 5];
	[NSURLConnection sendSynchronousRequest: request
										 returningResponse: &response error: nil];

	[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;

	return ([response statusCode] == 200);
}

- (BOOL)zapTo:(NSObject<ServiceProtocol> *) service
{
	// Generate URI
	NSURL *myURI = [NSURL URLWithString: [NSString stringWithFormat:@"/control/zapto?%@", [service.sref stringByAddingPercentEscapesUsingEncoding: NSUTF8StringEncoding]] relativeToURL: _baseAddress];

	[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;

	// Create URL Object and download it
	NSHTTPURLResponse *response;
	NSURLRequest *request = [NSURLRequest requestWithURL: myURI
											 cachePolicy: NSURLRequestReloadIgnoringCacheData timeoutInterval: 5];
	[NSURLConnection sendSynchronousRequest: request
										 returningResponse: &response error: nil];

	[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;

	// TODO: is the status code correct?
	return ([response statusCode] == 200);
}

- (BOOL)playMovie: (NSObject<MovieProtocol> *)movie
{
	[NSException raise:@"ExcUnsupportedFunction" format:nil];
	return NO;
}

/*
 Example:
 <?xml version="1.0" encoding="UTF-8"?>
 <zapit>
 <Bouquet type="0" bouquet_id="0000" name="Hauptsender" hidden="0" locked="0">
 <channel serviceID="d175" name="ProSieben" tsid="2718" onid="f001"/>
 </Bouquet>
 </zapit>
 */
- (void)refreshBouquetsXMLCache
{
	NSURL *myURI = [NSURL URLWithString: @"/control/getbouquetsxml" relativeToURL: _baseAddress];

	BaseXMLReader *streamReader = [[BaseXMLReader alloc] initWithTarget: nil action: nil];
	_cachedBouquetsXML = [[streamReader parseXMLFileAtURL: myURI parseError: nil] retain];
	[streamReader release];
}

- (CXMLDocument *)fetchBouquets:(id)target action:(SEL)action
{
	if(!_cachedBouquetsXML || [_cachedBouquetsXML retainCount] == 1)
	{
		[_cachedBouquetsXML release];
		[self refreshBouquetsXMLCache];
	}

	NSArray *resultNodes = NULL;
	NSUInteger parsedServicesCounter = 0;

	resultNodes = [_cachedBouquetsXML nodesForXPath:@"/zapit/Bouquet" error:nil];

	for(CXMLElement *resultElement in resultNodes)
	{
		if(++parsedServicesCounter >= MAX_SERVICES)
			break;

		// A channel in the xml represents a service, so create an instance of it.
		NSObject<ServiceProtocol> *newService = [[NeutrinoBouquet alloc] initWithNode: resultElement];

		[target performSelectorOnMainThread: action withObject: newService waitUntilDone: NO];
		[newService release];
	}

	// I don't assume we really need this but for the sake of it... :-)
	return _cachedBouquetsXML;
}

- (CXMLDocument *)fetchServices:(id)target action:(SEL)action bouquet:(NSObject<ServiceProtocol> *)bouquet
{
	NSArray *resultNodes = nil;
	NSUInteger parsedServicesCounter = 0;
	
	resultNodes = [bouquet nodesForXPath: @"channel" error: nil];
	if(!resultNodes || ![resultNodes count])
	{
		if(!_cachedBouquetsXML || [_cachedBouquetsXML retainCount] == 1)
		{
			[_cachedBouquetsXML release];
			[self refreshBouquetsXMLCache];
		}
		
		resultNodes = [_cachedBouquetsXML nodesForXPath:
						[NSString stringWithFormat: @"/zapit/Bouquet[@name=\"%@\"]/channel", bouquet.sname]
						error:nil];
	}

	for(CXMLElement *resultElement in resultNodes)
	{
		if(++parsedServicesCounter >= MAX_SERVICES)
			break;

		// A channel in the xml represents a service, so create an instance of it.
		NSObject<ServiceProtocol> *newService = [[Service alloc] init];

		newService.sname = [[resultElement attributeForName: @"name"] stringValue];
		newService.sref = [NSString stringWithFormat: @"%@%@%@",
						   [[resultElement attributeForName: @"tsid"] stringValue],
						   [[resultElement attributeForName: @"onid"] stringValue],
						   [[resultElement attributeForName: @"serviceID"] stringValue]];

		[target performSelectorOnMainThread: action withObject: newService waitUntilDone: NO];
		[newService release];
	}

	// I don't assume we really need this but for the sake of it... :-)
	return _cachedBouquetsXML;
}

- (CXMLDocument *)fetchEPG:(id)target action:(SEL)action service:(NSObject<ServiceProtocol> *)service
{
	// XXX: Maybe we should not hardcode "max"
	NSURL *myURI = [NSURL URLWithString: [NSString stringWithFormat:@"/control/epg?xml=true&channelid=%@&details=true&max=100", service.sref] relativeToURL: _baseAddress];

	BaseXMLReader *streamReader = [[NeutrinoEventXMLReader alloc] initWithTarget: target action: action];
	CXMLDocument *doc = [streamReader parseXMLFileAtURL: myURI parseError: nil];
	[streamReader autorelease];
	return doc;
}

// TODO: reimplement this as streaming parser some day :-)
- (CXMLDocument *)fetchTimers:(id)target action:(SEL)action
{
	// Refresh Service Cache if empty, we need it later when resolving service references
	if(!_cachedBouquetsXML)
		[self refreshBouquetsXMLCache];

	// Generate URI
	NSURL *myURI = [NSURL URLWithString: @"/control/timer" relativeToURL: _baseAddress];

	[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;

	// Create URL Object and download it
	NSURLResponse *response;
	NSError *error;
	NSURLRequest *request = [NSURLRequest requestWithURL: myURI
											 cachePolicy: NSURLRequestReloadIgnoringCacheData timeoutInterval: 5];
	NSData *data = [NSURLConnection sendSynchronousRequest: request
						  returningResponse: &response error: &error];

	[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;

	// Error occured, so send fake object
	if(error || !data)
	{
		NSObject<TimerProtocol> *fakeObject = [[Timer alloc] init];
		fakeObject.title = NSLocalizedString(@"Error retrieving Data", @"");
		fakeObject.state = 0;
		fakeObject.valid = NO;
		[target performSelectorOnMainThread: action withObject: fakeObject waitUntilDone: NO];
		[fakeObject release];

		return nil;
	}

	// Parse
	NSArray *timerStringList = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] componentsSeparatedByString: @"\n"];
	for(NSString *timerString in timerStringList)
	{
		// eventID eventType eventRepeat repcount announceTime alarmTime stopTime data
		NSArray *timerStringComponents = [timerString componentsSeparatedByString:@" "];

		if([timerStringComponents count] < 8) // XXX: should not happen...
			continue;

		NSObject<TimerProtocol> *timer = [[Timer alloc] init];
		
		// Determine type, reject unhandled
		NSInteger timerType = [[timerStringComponents objectAtIndex: 1] integerValue];
		if(timerType == neutrinoTimerTypeRecord)
			timer.justplay = NO;
		else if(timerType == neutrinoTimerTypeZapto)
			timer.justplay = YES;
		else
		{
			[timer release];
			continue;
		}

		timer.eit = [timerStringComponents objectAtIndex: 0]; // XXX: actually wrong but we need it :-)
		timer.title = [NSString stringWithFormat: @"Timer %@", timer.eit];
		timer.repeated = [[timerStringComponents objectAtIndex: 2] integerValue]; // XXX: as long as we don't offer to edit this via gui we can just keep the value and not change it to some common interpretation
		timer.repeatcount = [[timerStringComponents objectAtIndex: 3] integerValue];
		[timer setBeginFromString: [timerStringComponents objectAtIndex: 5]];
		[timer setEndFromString: [timerStringComponents objectAtIndex: 6]];

		// Eventually fetch Service from our Cache
		NSRange objRange;
		objRange.location = 7;
		objRange.length = [timerStringComponents count] - 7;
		NSString *sname = [[timerStringComponents subarrayWithRange: objRange] componentsJoinedByString: @" "];

		NSObject<ServiceProtocol> *service = [[Service alloc] init];
		service.sname = sname;
		NSArray *resultNodes = [_cachedBouquetsXML nodesForXPath:
									[NSString stringWithFormat: @"/zapit/Bouquet/channel[@name=\"%@\"]", sname]
									error:nil];
		// XXX: do we really want this? we don't care about the sref :-)
		if([resultNodes count])
		{
			CXMLElement *resultElement = [resultNodes objectAtIndex: 0];
			service.sref = [NSString stringWithFormat: @"%@%@%@",
								[[resultElement attributeForName: @"tsid"] stringValue],
								[[resultElement attributeForName: @"onid"] stringValue],
								[[resultElement attributeForName: @"serviceID"] stringValue]];
		}
		else
		{
			// XXX: we set a fake sref here as the service is valid enough for timers...
			service.sref = @"dc";
		}
		timer.service = service;
		[service release];

		// Determine state
		NSDate *announce = [NSDate dateWithTimeIntervalSince1970:
									[[timerStringComponents objectAtIndex: 4] doubleValue]];
		if([announce timeIntervalSinceNow] > 0)
			timer.state = kTimerStateWaiting;
		else if([timer.begin timeIntervalSinceNow] > 0)
			timer.state = kTimerStatePrepared;
		else if([timer.end timeIntervalSinceNow] > 0)
			timer.state = kTimerStateRunning;
		else
			timer.state = kTimerStateFinished;

		[target performSelectorOnMainThread:action withObject:timer waitUntilDone:NO];
		[timer release];
	}

	return nil;
}

- (CXMLDocument *)fetchMovielist:(id)target action:(SEL)action
{
	// XXX: is this actually possible?
	return nil;
}

- (void)sendPowerstate: (NSString *) newState
{
	// Generate URI
	NSURL *myURI = [NSURL URLWithString: [NSString stringWithFormat:@"/control/%@", newState] relativeToURL: _baseAddress];

	[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;

	// Create URL Object and download it
	NSURLResponse *response;
	NSURLRequest *request = [NSURLRequest requestWithURL: myURI
											 cachePolicy: NSURLRequestReloadIgnoringCacheData timeoutInterval: 5];
	[NSURLConnection sendSynchronousRequest: request
										 returningResponse: &response error: nil];

	[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
}

- (void)shutdown
{
	[self sendPowerstate: @"shutdown"];
}

- (void)standby
{
	// Generate URI
	NSURL *myURI = [NSURL URLWithString: @"/control/standby" relativeToURL: _baseAddress];
	
	[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;

	// Create URL Object and download it
	NSURLResponse *response;
	NSURLRequest *request = [NSURLRequest requestWithURL: myURI
											 cachePolicy: NSURLRequestReloadIgnoringCacheData timeoutInterval: 5];
	NSData *data = [NSURLConnection sendSynchronousRequest: request
										 returningResponse: &response error: nil];

	NSString *myString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	BOOL equalsOn = [myString isEqualToString: @"on"];
	[myString release];
	if(equalsOn)
		myString = @"standby?off";
	else
		myString = @"standby?on";

	[self sendPowerstate: myString];

	[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
}

- (void)reboot
{
	[self sendPowerstate: @"reboot"];
}

- (void)restart
{
	// XXX: not available
}

- (void)getVolume:(id)target action:(SEL)action
{
	Volume *volumeObject = [[Volume alloc] init];

	// Generate URI (mute)
	NSURL *myURI = [NSURL URLWithString: @"/control/volume?status" relativeToURL: _baseAddress];
	
	[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
	
	// Create URL Object and download it
	NSURLResponse *response;
	NSURLRequest *request = [NSURLRequest requestWithURL: myURI
											 cachePolicy: NSURLRequestReloadIgnoringCacheData timeoutInterval: 5];
	NSData *data = [NSURLConnection sendSynchronousRequest: request
										 returningResponse: &response error: nil];
	
	NSString *myString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	if([myString isEqualToString: @"1"])
		volumeObject.ismuted = YES;
	else
		volumeObject.ismuted = NO;

	[myString release];

	// Generate URI (volume)
	myURI = [NSURL URLWithString: @"/control/volume" relativeToURL: _baseAddress];
	
	// Create URL Object and download it
	request = [NSURLRequest requestWithURL: myURI
							   cachePolicy: NSURLRequestReloadIgnoringCacheData timeoutInterval: 5];
	data = [NSURLConnection sendSynchronousRequest: request
						  returningResponse: &response error: nil];
	
	[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;

	myString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	volumeObject.current = [myString integerValue];

	[myString release];

	[target performSelectorOnMainThread:action withObject:volumeObject waitUntilDone:NO];
	[volumeObject release];
}

- (void)getSignal:(id)target action:(SEL)action
{
	[NSException raise:@"ExcUnsupportedFunction" format:nil];
}

- (BOOL)toggleMuted
{
	BOOL equalsRes = NO;
	// Generate URI
	NSURL *myURI = [NSURL URLWithString: @"/control/volume?status" relativeToURL: _baseAddress];
	
	[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
	
	// Create URL Object and download it
	NSURLResponse *response;
	NSURLRequest *request = [NSURLRequest requestWithURL: myURI
											 cachePolicy: NSURLRequestReloadIgnoringCacheData timeoutInterval: 5];
	NSData *data = [NSURLConnection sendSynchronousRequest: request
										 returningResponse: &response error: nil];

	NSString *myString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	equalsRes = [myString isEqualToString: @"1"];
	[myString release];
	if(equalsRes)
		myString = @"unmute";
	else
		myString = @"mute";

	// Generate new URI
	myURI = [NSURL URLWithString: [NSString stringWithFormat: @"/control/volume?%@", myString] relativeToURL: _baseAddress];

	// Create URL Object and download it
	request = [NSURLRequest requestWithURL: myURI
											 cachePolicy: NSURLRequestReloadIgnoringCacheData timeoutInterval: 5];
	[NSURLConnection sendSynchronousRequest: request
										 returningResponse: &response error: nil];

	[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;

	equalsRes = [myString isEqualToString: @"mute"];
	[myString release];
	return equalsRes;
}

- (BOOL)setVolume:(NSInteger) newVolume
{
	// neutrino expect volume to be a multiple of 5
	NSInteger diff = newVolume % 5;
	// XXX: to make this code easier we could just add/remove the diff but lets try it fair first :-)
	if(diff < 3)
		newVolume -= diff;
	else
		newVolume += diff;

	// Generate URI
	NSURL *myURI = [NSURL URLWithString: [NSString stringWithFormat: @"/control/volume?%d", newVolume] relativeToURL: _baseAddress];
	
	[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
	
	// Create URL Object and download it
	NSHTTPURLResponse *response;
	NSURLRequest *request = [NSURLRequest requestWithURL: myURI
											 cachePolicy: NSURLRequestReloadIgnoringCacheData timeoutInterval: 5];
	[NSURLConnection sendSynchronousRequest: request
						  returningResponse: &response error: nil];
	
	[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
	
	// Sourcecode suggests that they always return ok, so we only do this simple check
	return ([response statusCode] == 200);
}

- (BOOL)addTimer:(NSObject<TimerProtocol> *) newTimer
{
	// Generate URI
	// XXX: Fails if I try to format the whole URL by one stringWithFormat... type will be wrong and sref can't be read so the program will crash
	NSString *add = [NSString stringWithFormat: @"/control/timer?action=new&alarm=%d&stop=%d&type=", (int)[newTimer.begin timeIntervalSince1970], (int)[newTimer.end timeIntervalSince1970]];
	add = [add stringByAppendingFormat: @"%d", (newTimer.justplay) ? neutrinoTimerTypeZapto : neutrinoTimerTypeRecord];
	add = [add stringByAppendingString: @"&channel_name="];
	add = [add stringByAppendingString: [newTimer.service.sname stringByAddingPercentEscapesUsingEncoding: NSUTF8StringEncoding]];
	NSURL *myURI = [NSURL URLWithString: add relativeToURL: _baseAddress];
	
	[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
	
	// Create URL Object and download it
	NSHTTPURLResponse *response;
	NSURLRequest *request = [NSURLRequest requestWithURL: myURI
											 cachePolicy: NSURLRequestReloadIgnoringCacheData timeoutInterval: 5];
	[NSURLConnection sendSynchronousRequest: request
						  returningResponse: &response error: nil];
	
	[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
	
	// Sourcecode suggests that they always return ok, so we only do this simple check
	return ([response statusCode] == 200);
}

- (BOOL)editTimer:(NSObject<TimerProtocol> *) oldTimer: (NSObject<TimerProtocol> *) newTimer
{
	// Generate URI
	// XXX: Fails if I try to format the whole URL by one stringWithFormat... type will be wrong and sref can't be read so the program will crash
	NSString *add = [NSString stringWithFormat: @"/control/timer?action=modify&id=%@&alarm=%d&stop=%d&format=", oldTimer.eit, (int)[newTimer.begin timeIntervalSince1970], (int)[newTimer.end timeIntervalSince1970]];
	add = [add stringByAppendingFormat: @"%d", (newTimer.justplay) ? neutrinoTimerTypeZapto : neutrinoTimerTypeRecord];
	add = [add stringByAppendingString: @"&channel_name="];
	add = [add stringByAppendingString: [newTimer.service.sname stringByAddingPercentEscapesUsingEncoding: NSUTF8StringEncoding]];
	add = [add stringByAppendingString: @"&rep="];
	add = [add stringByAppendingFormat: @"%d", newTimer.repeated];
	add = [add stringByAppendingString: @"&repcount="];
	add = [add stringByAppendingFormat: @"%d", newTimer.repeatcount];
	NSURL *myURI = [NSURL URLWithString: add relativeToURL: _baseAddress];

	[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
	
	// Create URL Object and download it
	NSHTTPURLResponse *response;
	NSURLRequest *request = [NSURLRequest requestWithURL: myURI
											 cachePolicy: NSURLRequestReloadIgnoringCacheData timeoutInterval: 5];
	[NSURLConnection sendSynchronousRequest: request
						  returningResponse: &response error: nil];
	
	[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
	
	// Sourcecode suggests that they always return ok, so we only do this simple check
	return ([response statusCode] == 200);
}

- (BOOL)delTimer:(NSObject<TimerProtocol> *) oldTimer
{
	// Generate URI
	NSURL *myURI = [NSURL URLWithString: [NSString stringWithFormat: @"/control/timer?action=remove&id=%@", oldTimer.eit] relativeToURL: _baseAddress];

	[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;

	// Create URL Object and download it
	NSHTTPURLResponse *response;
	NSURLRequest *request = [NSURLRequest requestWithURL: myURI
											 cachePolicy: NSURLRequestReloadIgnoringCacheData timeoutInterval: 5];
	[NSURLConnection sendSynchronousRequest: request
										 returningResponse: &response error: nil];
	
	[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;

	// Sourcecode suggests that they always return ok, so we only do this simple check
	return ([response statusCode] == 200);
}

- (BOOL)sendButton:(NSInteger) type
{
	// We fake some button codes (namely tv/radio) so we have to be able to set a custom uri
	NSURL *myURI = nil;

	// Translate ButtonCodes
	NSString *buttonCode = nil;
	switch(type)
	{
		case kButtonCode0: buttonCode = @"KEY_0"; break;
		case kButtonCode1: buttonCode = @"KEY_1"; break;
		case kButtonCode2: buttonCode = @"KEY_2"; break;
		case kButtonCode3: buttonCode = @"KEY_3"; break;
		case kButtonCode4: buttonCode = @"KEY_4"; break;
		case kButtonCode5: buttonCode = @"KEY_5"; break;
		case kButtonCode6: buttonCode = @"KEY_6"; break;
		case kButtonCode7: buttonCode = @"KEY_7"; break;
		case kButtonCode8: buttonCode = @"KEY_8"; break;
		case kButtonCode9: buttonCode = @"KEY_9"; break;
		case kButtonCodeMenu: buttonCode = @"KEY_SETUP"; break;
		case kButtonCodeLeft: buttonCode = @"KEY_LEFT"; break;
		case kButtonCodeRight: buttonCode = @"KEY_RIGHT"; break;
		case kButtonCodeUp: buttonCode = @"KEY_UP"; break;
		case kButtonCodeDown: buttonCode = @"KEY_DOWN"; break;
		case kButtonCodeLame: buttonCode = @"KEY_HOME"; break;
		case kButtonCodeRed: buttonCode = @"KEY_RED"; break;
		case kButtonCodeGreen: buttonCode = @"KEY_GREEN"; break;
		case kButtonCodeYellow: buttonCode = @"KEY_YELLOW"; break;
		case kButtonCodeBlue: buttonCode = @"KEY_BLUE"; break;
		case kButtonCodeVolUp: buttonCode = @"KEY_VOLUMEUP"; break;
		case kButtonCodeVolDown: buttonCode = @"KEY_VOLUMEDOWN"; break;
		case kButtonCodeMute: buttonCode = @"KEY_MUTE"; break;
		case kButtonCodeHelp: buttonCode = @"KEY_HELP"; break;
		case kButtonCodePower: buttonCode = @"KEY_POWER"; break;
		case kButtonCodeOK: buttonCode = @"KEY_OK"; break;
		case kButtonCodeTV:
			myURI = [NSURL URLWithString: @"/control/setmode?tv" relativeToURL: _baseAddress];
			break;
		case kButtonCodeRadio:
			myURI = [NSURL URLWithString: @"/control/setmode?radio" relativeToURL: _baseAddress];
			break;
		//case kButtonCode: buttonCode = @"KEY_"; break; // meant for copy&paste ;-)
		default:
			break;
	}

	if(myURI == nil)
	{
		if(buttonCode == nil)
			return NO;

		// Generate URI
		myURI = [NSURL URLWithString: [NSString stringWithFormat: @"/control/rcem?%@", buttonCode] relativeToURL: _baseAddress];
	}

	[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;

	// Create URL Object and download it
	NSHTTPURLResponse *response;
	NSURLRequest *request = [NSURLRequest requestWithURL: myURI
											 cachePolicy: NSURLRequestReloadIgnoringCacheData timeoutInterval: 5];
	[NSURLConnection sendSynchronousRequest: request
										 returningResponse: &response error: nil];

	[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;

	// XXX: is this status code correct?
	return ([response statusCode] == 200);
}

- (BOOL)sendMessage:(NSString *)message: (NSString *)caption: (NSInteger)type: (NSInteger)timeout
{
	// Generate URI
	NSURL *myURI = [NSURL URLWithString: [NSString stringWithFormat: @"/control/message?%@=%@", type == kNeutrinoMessageTypeConfirmed ? @"nmsg" : @"popup", [message stringByAddingPercentEscapesUsingEncoding: NSUTF8StringEncoding]] relativeToURL: _baseAddress];

	[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;

	// Create URL Object and download it
	NSHTTPURLResponse *response;
	NSURLRequest *request = [NSURLRequest requestWithURL: myURI
											 cachePolicy: NSURLRequestReloadIgnoringCacheData timeoutInterval: 5];
	[NSURLConnection sendSynchronousRequest: request
										 returningResponse: &response error: nil];

	[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;

	// XXX: is this status code correct?
	return ([response statusCode] == 200);
}

- (NSInteger)getMaxMessageType
{
	return kNeutrinoMessageTypeMax;
}

- (NSString *)getMessageTitle: (NSInteger)type
{
	switch(type)
	{
		case kNeutrinoMessageTypeNormal:
			return NSLocalizedString(@"Normal", @"");
		case kNeutrinoMessageTypeConfirmed:
			return NSLocalizedString(@"Confirmed", @"");
		default:
			return @"???";
	}
}

- (NSData *)getScreenshot: (enum screenshotType)type
{
	if(type == kScreenshotTypeOSD)
	{
		// Generate URI
		NSURL *myURI = [NSURL URLWithString: @"/GLJ-snapBMP.htm" relativeToURL: _baseAddress];

		[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;

		// Create URL Object and download it
		NSHTTPURLResponse *response;
		NSURLRequest *request = [NSURLRequest requestWithURL: myURI
												 cachePolicy: NSURLRequestReloadIgnoringCacheData timeoutInterval: 5];
		[NSURLConnection sendSynchronousRequest: request
							  returningResponse: &response error: nil];

		if([response statusCode] == 200)
		{
			// Generate URI
			myURI = [NSURL URLWithString: @"/control/exec?gljtool&fbsh_bmp" relativeToURL: _baseAddress];
			
			// Create URL Object and download it
			request = [NSURLRequest requestWithURL: myURI
									   cachePolicy: NSURLRequestReloadIgnoringCacheData timeoutInterval: 5];
			NSData *data = [NSURLConnection sendSynchronousRequest: request
												 returningResponse: &response error: nil];

			[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;

			return data;
		}

		// Generate URI
		myURI = [NSURL URLWithString: @"/control/exec?Y_Tools&fbshot&-r&-o&/tmp/dreaMote_Screenshot.bmp" relativeToURL: _baseAddress];
		
		// Create URL Object and download it
		request = [NSURLRequest requestWithURL: myURI
												 cachePolicy: NSURLRequestReloadIgnoringCacheData timeoutInterval: 5];
		[NSURLConnection sendSynchronousRequest: request
											 returningResponse: &response error: nil];

		// do we actually get a status != 200 back?
		// maybe check if data is not empty...
		if([response statusCode] != 200)
		{
			// Generate URI
			myURI = [NSURL URLWithString: @"/control/exec?Y_Tools&fbshot&-o&/tmp/dreaMote_Screenshot.bmp" relativeToURL: _baseAddress];

			// Create URL Object and download it
			request = [NSURLRequest requestWithURL: myURI
										cachePolicy: NSURLRequestReloadIgnoringCacheData timeoutInterval: 5];
			[NSURLConnection sendSynchronousRequest: request
												returningResponse: &response error: nil];
		}

		// Generate URI
		myURI = [NSURL URLWithString: @"/tmp/dreaMote_Screenshot.bmp" relativeToURL: _baseAddress];

		// Create URL Object and download it
		request = [NSURLRequest requestWithURL: myURI
								   cachePolicy: NSURLRequestReloadIgnoringCacheData timeoutInterval: 5];
		NSData *data = [NSURLConnection sendSynchronousRequest: request
											 returningResponse: &response error: nil];

		// Generate URI
		myURI = [NSURL URLWithString: @"/control/exec?Y_Tools&fbshot_clear" relativeToURL: _baseAddress];
		
		// Create URL Object and download it
		request = [NSURLRequest requestWithURL: myURI
								   cachePolicy: NSURLRequestReloadIgnoringCacheData timeoutInterval: 5];
		[NSURLConnection sendSynchronousRequest: request
							  returningResponse: &response error: nil];
		
		[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
		
		return data;
	}
	else// We actually generate a combined picture here
	{
		// We need to trigger a capture and individually fetch the picture
		// Generate URI
		NSURL *myURI = [NSURL URLWithString: @"/control/exec?Y_Tools&fbshot&fb&-q&/tmp/dreaMote_Screenshot.png" relativeToURL: _baseAddress];
		
		[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
		
		// Create URL Object and download it
		NSURLResponse *response;
		NSURLRequest *request = [NSURLRequest requestWithURL: myURI
												 cachePolicy: NSURLRequestReloadIgnoringCacheData timeoutInterval: 5];
		[NSURLConnection sendSynchronousRequest: request
											 returningResponse: &response error: nil];

		// XXX: check status?

		// Generate URI
		myURI = [NSURL URLWithString: @"/tmp/dreaMote_Screenshot.png" relativeToURL: _baseAddress];

		// Create URL Object and download it
		request = [NSURLRequest requestWithURL: myURI
								   cachePolicy: NSURLRequestReloadIgnoringCacheData timeoutInterval: 5];
		NSData *data = [NSURLConnection sendSynchronousRequest: request
									 returningResponse: &response error: nil];

		// Generate URI
		myURI = [NSURL URLWithString: @"/control/exec?Y_Tools&fbshot_clear" relativeToURL: _baseAddress];
		
		// Create URL Object and download it
		request = [NSURLRequest requestWithURL: myURI
								   cachePolicy: NSURLRequestReloadIgnoringCacheData timeoutInterval: 5];
		[NSURLConnection sendSynchronousRequest: request
											 returningResponse: &response error: nil];

		[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;

		return data;
	}

	return nil;
}

- (BOOL)delMovie:(NSObject<MovieProtocol> *) movie
{
	[NSException raise:@"ExcUnsupportedFunction" format:nil];
	return NO;
}

- (CXMLDocument *)searchEPG:(id)target action:(SEL)action title:(NSString *)title
{
	[NSException raise:@"ExcUnsupportedFunction" format:nil];
	return nil;
}

- (CXMLDocument *)searchEPGSimilar:(id)target action:(SEL)action event:(NSObject<EventProtocol> *)event
{
	[NSException raise:@"ExcUnsupportedFunction" format:nil];
	return nil;
}

- (BOOL)instantRecord
{
	[NSException raise:@"ExcUnsupportedFunction" format:nil];
	return NO;
}

- (void)openRCEmulator: (UINavigationController *)navigationController
{
	UIViewController *targetViewController = [[NeutrinoRCEmulatorController alloc] init];
	[navigationController pushViewController:targetViewController animated:YES];
	[targetViewController release];
}

- (void)freeCaches
{
	[_cachedBouquetsXML release];
	_cachedBouquetsXML = nil;
}

@end
