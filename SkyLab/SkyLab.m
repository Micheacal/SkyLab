// SkyLab.m
//
// Copyright (c) 2012 Mattt Thompson (http://mattt.me/)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "SkyLab.h"

#include <stdlib.h>

NSString * const SkyLabWillRunTestNotification = @"SkyLabWillRunTestNotification";
NSString * const SkyLabDidRunTestNotification = @"SkyLabDidRunTestNotification";
NSString * const SkyLabDidResetTestNotification = @"SkyLabDidResetTestNotification";

NSString * const SkyLabChoiceKey = @"SkyLabChoice";
NSString * const SkyLabActiveVariablesKey = @"SkyLabActiveVariables";

static NSString * SLUserDefaultsKeyForTestName(NSString *name) {
    static NSString * const kSLUserDefaultsKeyFormat = @"SkyLab-%@";

    return [NSString stringWithFormat:kSLUserDefaultsKeyFormat, name];
}

static id SLRandomValueFromArray(NSArray *array) {
    if ([array count] == 0) {
        return nil;
    }
    
    int idx = arc4random_uniform([array count]);
    return [array objectAtIndex:idx];
}

static dispatch_once_t srand48OnceToken;

static id SLRandomKeyFromDictionaryWithWeightedValues(NSDictionary *dictionary) {
    if ([dictionary count] == 0) {
        return nil;
    }
    
    NSArray *keys = [dictionary allKeys];
    NSMutableArray *mutableWeightedSums = [NSMutableArray arrayWithCapacity:[keys count]];
    
    double total = 0.0;
    for (id key in keys) {
        total += [[dictionary valueForKey:key] doubleValue];
        [mutableWeightedSums addObject:[NSNumber numberWithDouble:total]];
    }
    
    dispatch_once(&srand48OnceToken, ^{
        srand48(time(0));
    });
    
    double r = drand48() * total;
    
    __block id randomObject = nil;
    [mutableWeightedSums enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        double max = [obj doubleValue];
        if (r <= max) {
            randomObject = [keys objectAtIndex:idx];
            *stop = YES;
        }
    }];
    
    return randomObject;
}

static BOOL SLRandomBinaryChoiceWithProbability(double p) {
    dispatch_once(&srand48OnceToken, ^{
        srand48(time(0));
    });
    
    return drand48() <= p;
}

static BOOL SLRandomBinaryChoice() {
    return SLRandomBinaryChoiceWithProbability(0.5);
}

@implementation SkyLab

+ (void)abTestWithName:(NSString *)name
                     A:(void (^)())A
                     B:(void (^)())B
{
    [self splitTestWithName:name choices:[NSArray arrayWithObjects:@"A", @"B", nil] block:^(NSString *choice) {
        if ([choice isEqualToString:@"A"] && A) {
            A();
        } else if ([choice isEqualToString:@"B"] && B) {
            B();
        }
    }];
}

+ (void)splitTestWithName:(NSString *)name
                  choices:(id)choices
                    block:(void (^)(id choice))block
{
    NSParameterAssert([choices isKindOfClass:[NSArray class]] || [choices isKindOfClass:[NSDictionary class]]);

    if (!block) {
        return;
    }
    
    id choice = [[NSUserDefaults standardUserDefaults] objectForKey:SLUserDefaultsKeyForTestName(name)];
    
    if ([choices isKindOfClass:[NSArray class]]) {
        if (!choice || ![choices containsObject:choice]) {
            choice = SLRandomValueFromArray(choices);
        }
    } else if ([choices isKindOfClass:[NSDictionary class]]) {
        if (!choice || ![[choices allKeys] containsObject:choice]) {
            choice = SLRandomKeyFromDictionaryWithWeightedValues(choices);
        }
    }

    [[NSUserDefaults standardUserDefaults] setObject:choice forKey:SLUserDefaultsKeyForTestName(name)];

    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:choice forKey:SkyLabChoiceKey];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:SkyLabWillRunTestNotification object:name userInfo:userInfo];
    block(choice);
    [[NSNotificationCenter defaultCenter] postNotificationName:SkyLabDidRunTestNotification object:name userInfo:userInfo];
}

+ (void)multivariateTestWithName:(NSString *)name
                       variables:(id)variables
                           block:(void (^)(NSSet *activeVariables))block
{
    NSParameterAssert([variables isKindOfClass:[NSArray class]] || [variables isKindOfClass:[NSDictionary class]]);

    if (!block) {
        return;
    }
    
    NSSet *activeVariables = [NSSet setWithArray:[[NSUserDefaults standardUserDefaults] objectForKey:SLUserDefaultsKeyForTestName(name)]];
    
    if ([variables isKindOfClass:[NSArray class]]) {
        if (!activeVariables || ![activeVariables isKindOfClass:[NSSet class]] || ![activeVariables intersectsSet:[NSSet setWithArray:variables]]) {
            NSMutableSet *mutableActiveVariables = [NSMutableSet setWithCapacity:[variables count]];
            [variables enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                if (SLRandomBinaryChoice()) {
                    [mutableActiveVariables addObject:obj];
                }
            }];
            activeVariables = mutableActiveVariables;
        }
    } else if ([variables isKindOfClass:[NSDictionary class]]) {
        if (!activeVariables || ![activeVariables isKindOfClass:[NSSet class]] || ![activeVariables intersectsSet:[NSSet setWithArray:[variables allKeys]]]) {
            NSMutableSet *mutableActiveVariables = [NSMutableSet setWithCapacity:[variables count]];
            [variables enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                if (SLRandomBinaryChoiceWithProbability([obj doubleValue])) {
                    [mutableActiveVariables addObject:key];
                }
            }];
            activeVariables = mutableActiveVariables;
        }
    }
    
    [[NSUserDefaults standardUserDefaults] setObject:[activeVariables allObjects] forKey:SLUserDefaultsKeyForTestName(name)];

    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:activeVariables forKey:SkyLabActiveVariablesKey];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:SkyLabWillRunTestNotification object:name userInfo:userInfo];
    block(activeVariables);
    [[NSNotificationCenter defaultCenter] postNotificationName:SkyLabDidRunTestNotification object:name userInfo:userInfo];
}

+ (void)resetTestNamed:(NSString *)name {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:SLUserDefaultsKeyForTestName(name)];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:SkyLabDidResetTestNotification object:name];
}

@end
