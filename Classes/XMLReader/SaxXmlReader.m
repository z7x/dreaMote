//
//  SaxXmlReader.m
//  dreaMote
//
//  Created by Moritz Venn on 15.01.11.
//  Copyright 2011 Moritz Venn. All rights reserved.
//

#import "SaxXmlReader.h"

#import "AppDelegate.h"
#import "RemoteConnectorObject.h"

#import "NSObject+Queue.h"

@interface SaxXmlReader()
- (void)charactersFound:(const xmlChar *)characters length:(int)length;
- (void)parsingError:(const char *)msg, ...;
- (void)endDocument;
@end

// formward declare
static xmlSAXHandler libxmlSAXHandlerStruct;

@implementation SaxXmlReader

@synthesize currentString, currentItems;

- (void)dealloc
{
	xmlFreeParserCtxt(_xmlParserContext);
	_xmlParserContext = NULL;
}

- (CXMLDocument *)parseXMLFileAtURL: (NSURL *)URL parseError: (NSError **)error
{
	@autoreleasepool
	{
	NSURLRequest *request = [[NSURLRequest alloc] initWithURL:URL
												  cachePolicy:NSURLRequestReloadIgnoringCacheData
											  timeoutInterval:_timeout];
	NSURLConnection *con = nil;

	if(request)
		con = [[NSURLConnection alloc] initWithRequest:request delegate:self];
#if IS_DEBUG()
	else
		[NSException raise:@"ExcSaxXmlReaderNoRequest" format:@""];
#endif

	if(con)
	{
		[APP_DELEGATE addNetworkOperation];
		_xmlParserContext = xmlCreatePushParserCtxt(&libxmlSAXHandlerStruct, (__bridge void *)(self), NULL, 0, NULL);
		xmlCtxtUseOptions(_xmlParserContext, XML_PARSE_NOENT);

		while(!_done)
		{
			[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
		}
		[con cancel]; // just in case, cancel the connection
		[APP_DELEGATE removeNetworkOperation];

		xmlFreeParserCtxt(_xmlParserContext);
		_xmlParserContext = NULL;
	}
	else
	{
#if IS_DEBUG()
		[NSException raise:@"ExcSaxXmlReaderNoConnection" format:@""];
#else
		NSDictionary *userInfo = [NSDictionary dictionaryWithObject:NSLocalizedString(@"Unknown connection error occured.", @"Data connection failed for unknown reason.")
															 forKey:NSLocalizedDescriptionKey];
		failureReason = [NSError errorWithDomain:@"myDomain"
											code:900
										userInfo:userInfo];
#endif
	}

	if(failureReason)
	{
		[self sendErroneousObject];

		// delegate wants to be informated about errors
		SEL errorParsing = @selector(dataSourceDelegate:errorParsingDocument:);
		NSMethodSignature *sig = [_delegate methodSignatureForSelector:errorParsing];
		if(_delegate && [_delegate respondsToSelector:errorParsing] && sig)
		{
			BaseXMLReader *__unsafe_unretained dataSource = self;
			NSError *__unsafe_unretained dataSourceError = failureReason;
			NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:sig];
			[invocation retainArguments];
			[invocation setTarget:_delegate];
			[invocation setSelector:errorParsing];
			[invocation setArgument:&dataSource atIndex:2];
			[invocation setArgument:&dataSourceError atIndex:3];
			[invocation performSelectorOnMainThread:@selector(invoke) withObject:NULL
									  waitUntilDone:NO];
		}
	}
	else
	{
		[[self queueOnMainThread] finishedParsingDocument];
	}
	} // /@autoreleasepool
	return nil;
}

- (void)finishedParsingDocument
{
	if([_delegate respondsToSelector:@selector(dataSourceDelegateFinishedParsingDocument:)])
	{
		[_delegate dataSourceDelegateFinishedParsingDocument:self];
	}
}

#pragma mark -
#pragma mark libxml2 objc callbacks
#pragma mark -

- (void)charactersFound:(const xmlChar *)characters length:(int)length
{
	if(currentString)
	{
		NSString *value = [[NSString alloc] initWithBytes:(const void *)characters
												   length:length
												 encoding:self.encoding];
		[currentString appendString:value];
	}
}

- (void)parsingError:(const char *)msg, ...
{
	NSString *format = [[NSString alloc] initWithBytes:msg
												length:strlen(msg)
											  encoding:NSUTF8StringEncoding];
	CFStringRef resultString = NULL;
	va_list argList;
	va_start(argList, msg);
	resultString = CFStringCreateWithFormatAndArguments(NULL, NULL, (__bridge CFStringRef)format, argList);
	va_end(argList);

	NSDictionary *userInfo = [NSDictionary dictionaryWithObject:(__bridge NSString*)resultString forKey:NSLocalizedDescriptionKey];
	NSError *error = [NSError errorWithDomain:@"ParsingDomain" code:101 userInfo:userInfo];

	failureReason = error;
	_done = YES;

	CFRelease(resultString);
}

- (void)endDocument
{
	_done = YES;
}

#pragma mark dummy methods

- (void)elementFound:(const xmlChar *)localname prefix:(const xmlChar *)prefix uri:(const xmlChar *)URI namespaceCount:(int)namespaceCount namespaces:(const xmlChar **)namespaces attributeCount:(int)attributeCount defaultAttributeCount:(int)defaultAttributeCount attributes:(xmlSAX2Attributes *)attributes
{
	// dummy
}

- (void)endElement:(const xmlChar *)localname prefix:(const xmlChar *)prefix uri:(const xmlChar *)URI
{
	// dummy
}

- (void)sendErroneousObject
{
	// dummy
}

#pragma mark -
#pragma mark NSURLConnection delegate methods
#pragma mark -

- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace
{
	return YES;
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
	if([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust])
	{
		// TODO: ask user to accept certificate
		[challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]
			 forAuthenticationChallenge:challenge];
		return;
	}
	else if([challenge previousFailureCount] < 2) // ssl might have failed already
	{
		NSURLCredential *creds = [RemoteConnectorObject getCredential];
		if(creds)
		{
			[challenge.sender useCredential:creds forAuthenticationChallenge:challenge];
			return;
		}
	}

	// NOTE: continue just swallows all errors while cancel gives a weird message,
	// but a weird message is better than no response
	//[challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
	[challenge.sender cancelAuthenticationChallenge:challenge];
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse
{
	return nil;
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
	failureReason = error;

	_done = YES;
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
	xmlParseChunk(_xmlParserContext, (const char *)[data bytes], [data length], 0);
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
	if([response respondsToSelector:@selector(statusCode)])
	{
		NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
		if (statusCode > 399)
		{
			NSDictionary *userInfo = [NSDictionary dictionaryWithObject:[NSString stringWithFormat:NSLocalizedString(@"Connection to remote host failed with status code %d.", @""), statusCode]
																 forKey:NSLocalizedDescriptionKey];
			NSError *error = [NSError errorWithDomain:NSURLErrorDomain
												 code:statusCode
											 userInfo:userInfo];
			[self connection:connection didFailWithError:error];
		}
	}
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
	xmlParseChunk(_xmlParserContext, NULL, 0, 1);
	// NOTE: don't set _done, instead let the parser to it because it will be destroyed afterwards
}

@end

#pragma mark -
#pragma mark libxml2 c callbacks
#pragma mark -

static void startElementSAX(void *ctx, const xmlChar *localname, const xmlChar *prefix, const xmlChar *URI, int nb_namespaces, const xmlChar **namespaces, int nb_attributes, int nb_defaulted, const xmlChar **attributes)
{
	[(__bridge SaxXmlReader *)ctx elementFound:localname
										prefix:prefix
										   uri:URI
								namespaceCount:nb_namespaces
									namespaces:namespaces
								attributeCount:nb_attributes
						 defaultAttributeCount:nb_defaulted
									attributes:(xmlSAX2Attributes*)attributes];
}

static void	endElementSAX(void *ctx, const xmlChar *localname, const xmlChar *prefix, const xmlChar *URI)
{
	[(__bridge SaxXmlReader *)ctx endElement:localname prefix:prefix uri:URI];
}

static void	charactersFoundSAX(void *ctx, const xmlChar *ch, int len)
{
	[(__bridge SaxXmlReader *)ctx charactersFound:ch length:len];
}

static void errorEncounteredSAX(void *ctx, const char *msg, ...)
{
	va_list argList;
	va_start(argList, msg);
	[(__bridge SaxXmlReader *)ctx parsingError:msg, argList];
}

static void endDocumentSAX(void *ctx)
{
	[(__bridge SaxXmlReader *)ctx endDocument];
}

static xmlSAXHandler libxmlSAXHandlerStruct =
{
	NULL,						/* internalSubset */
	NULL,						/* isStandalone */
	NULL,						/* hasInternalSubset */
	NULL,						/* hasExternalSubset */
	NULL,						/* resolveEntity */
	NULL,						/* getEntity */
	NULL,						/* entityDecl */
	NULL,						/* notationDecl */
	NULL,						/* attributeDecl */
	NULL,						/* elementDecl */
	NULL,						/* unparsedEntityDecl */
	NULL,						/* setDocumentLocator */
	NULL,						/* startDocument */
	endDocumentSAX,				/* endDocument */
	NULL,						/* startElement*/
	NULL,						/* endElement */
	NULL,						/* reference */
	charactersFoundSAX,			/* characters */
	NULL,						/* ignorableWhitespace */
	NULL,						/* processingInstruction */
	NULL,						/* comment */
	NULL,						/* warning */
	errorEncounteredSAX,		/* error */
	NULL,						/* fatalError //: unused error() get all the errors */
	NULL,						/* getParameterEntity */
	NULL,						/* cdataBlock */
	NULL,						/* externalSubset */
	XML_SAX2_MAGIC,				/* initialized */
	NULL,						/* private */
	startElementSAX,			/* startElementNs */
	endElementSAX,				/* endElementNs */
	NULL,						/* serror */
};
