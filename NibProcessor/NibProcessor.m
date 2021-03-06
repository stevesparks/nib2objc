//
//  NibProcessor.m
//  nib2objc
//
//  Created by Adrian on 3/13/09.
//  Adrian Kosmaczewski 2009
//

#import "NibProcessor.h"
#import "Processor.h"
#import "NSString+Nib2ObjcExtensions.h"

@interface NibProcessor ()

- (void)getDictionaryFromNIB;
- (void)parseChildren:(NSDictionary *)dict ofCurrentView:(int)currentView withObjects:(NSDictionary *)objects;
- (NSString *)instanceNameForObject:(id)obj;

@end


@implementation NibProcessor

@dynamic input;
@synthesize output = _output;
@synthesize codeStyle = _codeStyle;

- (id)init
{
    if (self = [super init])
    {
        self.codeStyle = NibProcessorCodeStyleProperties;
    }
    return self;
}

- (void)dealloc
{
    [_filename release];
    [_output release];
    [_dictionary release];
    [_data release];
    [super dealloc];
}

#pragma mark -
#pragma mark Properties

- (NSString *)input
{
    return _filename;
}

- (void)setInput:(NSString *)newFilename
{
    [_filename release];
    _filename = nil;
    _filename = [newFilename copy];
    [self getDictionaryFromNIB];
}

- (NSString *)inputAsText
{
    return [[[NSString alloc] initWithData:_data encoding:NSUTF8StringEncoding] autorelease];
}

- (NSDictionary *)inputAsDictionary
{
    NSString *errorStr = nil;
    NSPropertyListFormat format;
    NSDictionary *propertyList = [NSPropertyListSerialization propertyListFromData:_data
                                                                  mutabilityOption:NSPropertyListImmutable
                                                                            format:&format
                                                                  errorDescription:&errorStr];
    [errorStr release];
    return propertyList;    
}

#pragma mark -
#pragma mark Private methods

- (void)getDictionaryFromNIB
{
    // Build the NSTask that will run the ibtool utility
    NSArray *arguments = [NSArray arrayWithObjects:_filename, @"--objects", 
                          @"--hierarchy", @"--connections", @"--classes", nil];
    NSTask *task = [[NSTask alloc] init];
    NSPipe *pipe = [NSPipe pipe];
    NSFileHandle *readHandle = [pipe fileHandleForReading];
    NSData *temp = nil;

    [_data release];
    _data = [[NSMutableData alloc] init];
    
    [task setLaunchPath:@"/usr/bin/ibtool"];
    [task setArguments:arguments];
    [task setStandardOutput:pipe];
    [task launch];
    
    while ((temp = [readHandle availableData]) && [temp length]) 
    {
        [_data appendData:temp];
    }

    // This dictionary is ready to be parsed, and it contains
    // everything we need from the NIB file.
    _dictionary = [[self inputAsDictionary] retain];
    
    [task release];
}

- (void)process
{
    //    NSDictionary *nibClasses = [dict objectForKey:@"com.apple.ibtool.document.classes"];
	NSDictionary *nibConnections = [_dictionary objectForKey:@"com.apple.ibtool.document.connections"];
    NSDictionary *nibObjects = [_dictionary objectForKey:@"com.apple.ibtool.document.objects"];
    NSMutableDictionary *objects = [[NSMutableDictionary alloc] init];
    
    for (NSDictionary *key in nibObjects)
    {
        id object = [nibObjects objectForKey:key];
        NSString *klass = [object objectForKey:@"class"];

        Processor *processor = [Processor processorForClass:klass];

        if (processor == nil)
        {
#ifdef CONFIGURATION_Debug
            // Get notified about classes not yet handled by this utility
            NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
            [dict setObject:klass forKey:@"// unknown object (yet)"];
            [objects setObject:dict forKey:key];
            [dict release];
#endif
        }
        else
        {
            NSDictionary *dict = [processor processObject:object];
            [objects setObject:dict forKey:key];
        }
    }
    
    // Let's print everything as source code
    [_output release];
    _output = [[NSMutableString alloc] init];
    for (NSString *identifier in objects)
    {
        id object = [objects objectForKey:identifier];
        NSString *identifierKey = [[identifier stringByReplacingOccurrencesOfString:@"-" withString:@""] lowercaseString];
        
        // First, output any helper functions, ordered alphabetically
        NSArray *orderedKeys = [object keysSortedByValueUsingSelector:@selector(caseInsensitiveCompare:)];
        for (NSString *key in orderedKeys)
        {
            id value = [object objectForKey:key];
            if ([key hasPrefix:@"__helper__"])
            {
                [_output appendString:value];
                [_output appendString:@"\n"];    
            }
        }
        
        // Then, output the constructor
        id klass = [object objectForKey:@"class"];
        id constructor = [object objectForKey:@"constructor"];
        NSString *instanceName = [self instanceNameForObject:object];
        [_output appendFormat:@"%@ *%@%@ = %@;\n", klass, instanceName, identifierKey, constructor];
                
        // Then, output the properties only, ordered alphabetically
        orderedKeys = [[object allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
        for (NSString *key in orderedKeys)
        {
            id value = [object objectForKey:key];
            if (![key hasPrefix:@"__method__"] 
                && ![key isEqualToString:@"constructor"] && ![key isEqualToString:@"class"]
                && ![key hasPrefix:@"__helper__"])
            {
                switch (self.codeStyle) 
                {
                    case NibProcessorCodeStyleProperties:
                        [_output appendFormat:@"%@%@.%@ = %@;\n", instanceName, identifierKey, key, value];
                        break;
                        
                    case NibProcessorCodeStyleSetter:
                        [_output appendFormat:@"[%@%@ set%@:%@];\n", instanceName, identifierKey, [key capitalize], value];
                        break;
                        
                    default:
                        break;
                }
            }
        }

        // Finally, output the method calls, ordered alphabetically
        orderedKeys = [object keysSortedByValueUsingSelector:@selector(caseInsensitiveCompare:)];
        for (NSString *key in orderedKeys)
        {
            id value = [object objectForKey:key];
            if ([key hasPrefix:@"__method__"])
            {
                [_output appendFormat:@"[%@%@ %@];\n", instanceName, identifierKey, value];
            }
        }
        [_output appendString:@"\n"];    
    }
    
    // Now that the objects are created, recreate the hierarchy of the NIB
    NSArray *nibHierarchy = [_dictionary objectForKey:@"com.apple.ibtool.document.hierarchy"];
    for (NSDictionary *item in nibHierarchy)
    {
        int currentView = [[item objectForKey:@"object-id"] intValue];
        [self parseChildren:item ofCurrentView:currentView withObjects:objects];
    }

	// Last, wire it up
    [self connectObjects:objects usingNibConnections:nibConnections ];


	



    [objects release];
    objects = nil;
}



- (void)parseChildren:(NSDictionary *)dict ofCurrentView:(int)currentView withObjects:(NSDictionary *)objects
{
    NSArray *children = [dict objectForKey:@"children"];
    if (children != nil)
    {
        for (NSDictionary *subitem in children)
        {
            int subview = [[subitem objectForKey:@"object-id"] intValue];

            id currentViewObject = [objects objectForKey:[NSString stringWithFormat:@"%d", currentView]];
            NSString *instanceName = [self instanceNameForObject:currentViewObject];
            
            id subViewObject = [objects objectForKey:[NSString stringWithFormat:@"%d", subview]];
            NSString *subInstanceName = [self instanceNameForObject:subViewObject];
            
            [self parseChildren:subitem ofCurrentView:subview withObjects:objects];
            [_output appendFormat:@"[%@%d addSubview:%@%d];\n", instanceName, currentView, subInstanceName, subview];
        }
    }
}

- (NSString *)instanceNameForObject:(id)obj
{
    id klass = [obj objectForKey:@"class"];
    NSString *instanceName = [[klass lowercaseString] substringFromIndex:2];
    return instanceName;
}


- (NSString *) eventConstantForString:(NSString *)string {
	if([string isEqualToString:@"Touch Up Inside"])
		return @"UIControlEventTouchUpInside";
	if([string isEqualToString:@"Value Changed"])
		return @"UIControlEventTouchUpInside";
	if([string isEqualToString:@"Touch Down" ])
		return @"UIControlEventTouchDown";
	if([string isEqualToString:@"Touch Down Repeat" ])
		return @"UIControlEventTouchDownRepeat";
	if([string isEqualToString:@"Touch Drag Inside" ])
		return @"UIControlEventTouchDragInside";
	if([string isEqualToString:@"Touch Drag Outside" ])
		return @"UIControlEventTouchDragOutside";
	if([string isEqualToString:@"Touch Drag Enter" ])
		return @"UIControlEventTouchDragEnter";
	if([string isEqualToString:@"Touch Drag Exit" ])
		return @"UIControlEventTouchDragExit";
	if([string isEqualToString:@"Touch Up Inside" ])
		return @"UIControlEventTouchUpInside";
	if([string isEqualToString:@"Touch Up Outside" ])
		return @"UIControlEventTouchUpOutside";
	if([string isEqualToString:@"Touch Cancel" ])
		return @"UIControlEventTouchCancel";
	if([string isEqualToString:@"Value Changed" ])
		return @"UIControlEventValueChanged";
	if([string isEqualToString:@"Editing Did Begin" ])
		return @"UIControlEventEditingDidBegin";
	if([string isEqualToString:@"Editing Changed" ])
		return @"UIControlEventEditingChanged";
	if([string isEqualToString:@"Editing Did End" ])
		return @"UIControlEventEditingDidEnd";
	if([string isEqualToString:@"Editing Did End On Exit" ])
		return @"UIControlEventEditingDidEndOnExit";

	return [NSString stringWithFormat:@"*********** %@", string];

}

- (void)connectObjects:(NSDictionary *)objects usingNibConnections:(NSDictionary *)nibConnections {

	[_output appendFormat:@"// wire us up\n"];

	for(NSObject * key in [nibConnections allKeys]) {
		NSDictionary *connection = [nibConnections objectForKey:key];

		if(connection) {
			int dstId = [[connection objectForKey:@"destination-id"] intValue];
			int srcId = [[connection objectForKey:@"source-id"] intValue];

			NSDictionary *dstObj = [objects objectForKey:[NSString stringWithFormat:@"%d",dstId]];
			NSDictionary *srcObj = [objects objectForKey:[NSString stringWithFormat:@"%d",srcId]];

			if(dstObj) {
				NSString *srcLabel;
				NSString *dstLabel;

				if(dstId == -1) {
					dstLabel = @"owner";
				} else {
					dstLabel = [NSString stringWithFormat:@"%@%d", [self instanceNameForObject:dstObj], dstId];
				}

				if(srcId == -1) {
					srcLabel = @"owner";
				} else {
					srcLabel = [NSString stringWithFormat:@"%@%d", [self instanceNameForObject:srcObj], srcId];
				}

				NSString *outletLabel = [connection objectForKey:@"label"];
				NSString *type = [connection objectForKey:@"type"];

				if([type isEqualToString:@"IBCocoaTouchEventConnection"]) {
					NSString *eventConstant;
					for(id key in connection.allKeys) {
						id val = [connection objectForKey:key];
						if([@"event-type" isEqualTo:val]) {
							eventConstant = [self eventConstantForString:key];
						}
					}

					[_output appendFormat:@"[%@ addTarget:%@ action:@selector(%@) forControlEvents:%@ ];\n", srcLabel, dstLabel, outletLabel, eventConstant];
				} else if ([type isEqualToString:@"IBCocoaTouchOutletConnection"]) {
					[_output appendFormat:@"%@.%@ = %@;\n", srcLabel, outletLabel, dstLabel];
				} else
					NSLog(@"*** FAIL *** %@: %d -> %@\n\n%@\n\n", type, srcId, dstLabel, connection);

			} else {
				NSLog(@"WAT");
			}
		} else {
			NSLog(@"Couldn't find key [%@] ! keys are [%@]", key, [objects allKeys]);
		}

		//		NSString *source = [conn objectForKey:@""];
	}
}



@end
