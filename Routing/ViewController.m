//
//  ViewController.m
//  Routing
//
//  Created by Joseph Lin on 7/11/12.
//  Copyright (c) 2012 Joseph Lin. All rights reserved.
//

#import "ViewController.h"
#import "Route.h"
#import "PinAnnotation.h"
#import "MKPolyline+Decoding.h"

#define kStartPointTitle    @"Start"
#define kOtherPointTitle    @"Transfer"
#define kEndPointTitle      @"End"

static NSString* baseURL = @"http://maps.googleapis.com/maps/api/directions/json";


@interface ViewController () <CLLocationManagerDelegate>
@property (nonatomic, strong) CLLocationManager* locationManager;
@property (nonatomic, strong) MKDirectionsRequest* currentRequest;
@end


@implementation ViewController
@synthesize mapView;
@synthesize locationManager, currentRequest;


- (void)viewDidLoad
{
    [super viewDidLoad];
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

- (void)showLastRoute
{
    NSDictionary* dict = [NSKeyedUnarchiver unarchiveObjectWithFile:[self archivePath]];
    CLLocation* fromLocation = [dict objectForKey:@"fromLocation"];
    CLLocation* toLocation = [dict objectForKey:@"toLocation"];
    if ( fromLocation && toLocation )
    {
        [self findRouteFromLocation:fromLocation toLocation:toLocation];
    }
}

- (void)processRequest:(MKDirectionsRequest*)request;
{
    self.currentRequest = request;

    if ( [request.source isCurrentLocation] )
    {
        if ( !self.locationManager.location )
        {
            [self.locationManager startMonitoringSignificantLocationChanges];
        }
        else
        {
            [self findRouteFromLocation:self.locationManager.location toLocation:self.currentRequest.destination.placemark.location];
        }
    }
    else
    {
        [self findRouteFromLocation:request.source.placemark.location toLocation:request.destination.placemark.location];
    }
}

- (void)locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)newLocation fromLocation:(CLLocation *)oldLocation
{
    [self.locationManager stopMonitoringSignificantLocationChanges];
    
    if ( [self.currentRequest.source isCurrentLocation] )
    {
        [self findRouteFromLocation:self.locationManager.location toLocation:self.currentRequest.destination.placemark.location];
    }
}

- (void)findRouteFromLocation:(CLLocation*)fromLocation toLocation:(CLLocation*)toLocation
{
    NSDictionary* dict = [NSDictionary dictionaryWithObjectsAndKeys:
                          fromLocation, @"fromLocation",
                          toLocation, @"toLocation",
                          nil];   
    [NSKeyedArchiver archiveRootObject:dict toFile:[self archivePath]];


    NSString* fromLatLon = [NSString stringWithFormat:@"%f,%f", fromLocation.coordinate.latitude, fromLocation.coordinate.longitude];
    NSString* toLatLon = [NSString stringWithFormat:@"%f,%f", toLocation.coordinate.latitude, toLocation.coordinate.longitude];
    NSString* departureTime = [NSString stringWithFormat:@"%1.0f", [[NSDate date] timeIntervalSince1970]];
    NSDictionary* params = [NSDictionary dictionaryWithObjectsAndKeys:
                            fromLatLon, @"origin",
                            toLatLon, @"destination",
                            @"false", @"sensor",
                            @"transit", @"mode",
                            departureTime, @"departure_time",
                            nil];
    
    NSString* query = [self queryFromDictionary:params];
    NSString* URLString = [NSString stringWithFormat:@"%@?%@", baseURL, query];
    NSURL* URL = [NSURL URLWithString:URLString];
    NSURLRequest* request = [NSURLRequest requestWithURL:URL];
    
    NSLog(@"Request URL: %@", URL);

    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        
//        NSLog(@"HTTP Response: %@", response);
        if ( !error )
        {
            id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            [self processJSONResponse:object];
        }
    }];
}

- (void)processJSONResponse:(NSDictionary*)response
{
//    NSLog(@"Response: %@", response);

    NSArray* routes = [response objectForKey:@"routes"];
    
    if ( [routes count] )
    {
        Route *route = [Route routeWithDictionary:[routes objectAtIndex:0]];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self displayRoute:route];
        });
    }
}

- (void)displayRoute:(Route*)route
{
    self.mapView.region = route.bounds;

    NSArray* allSteps = [route valueForKeyPath:@"legs.@unionOfArrays.steps"];

    for ( int i = 0; i < [allSteps count]; i++ )
    {
        Step* step = [allSteps objectAtIndex:i];

        PinAnnotation* annotation = [PinAnnotation new];
        annotation.coordinate = step.startCoordinate;
        annotation.title = (i == 0) ? kStartPointTitle : kOtherPointTitle;
        annotation.subtitle = step.HTMLInstructions;
        [self.mapView addAnnotation:annotation];

        MKPolyline *polyline = [MKPolyline polylineWithEncodedString:step.polylineString];
        [self.mapView addOverlay:polyline];

        
        if (i == [allSteps count] - 1)
        {
            PinAnnotation* annotation = [PinAnnotation new];
            annotation.coordinate = step.endCoordinate;
            annotation.title = kEndPointTitle;
            [self.mapView addAnnotation:annotation];
        }
    }
    
    NSLog(@"Annotations: %@", self.mapView.annotations);
}



- (NSString*)queryFromDictionary:(NSDictionary*)dict
{
    NSMutableArray* pairs = [NSMutableArray arrayWithCapacity:[dict count]];
    
    [dict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        NSString* pair = [NSString stringWithFormat:@"%@=%@", key, obj];
        [pairs addObject:pair];
    }];
    
    NSString* query = [pairs componentsJoinedByString:@"&"];
    return query;
}

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id < MKAnnotation >)annotation
{
    static NSString* pinReuseIdentifier = @"pinReuseIdentifier";
    MKPinAnnotationView* pinAnnotationView = [[MKPinAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:pinReuseIdentifier];
    pinAnnotationView.canShowCallout = YES;
    if ([annotation.title isEqualToString:kStartPointTitle])
    {
        pinAnnotationView.pinColor = MKPinAnnotationColorRed;
    }
    else if ([annotation.title isEqualToString:kEndPointTitle])
    {
        pinAnnotationView.pinColor = MKPinAnnotationColorGreen;
    }
    else
    {
        pinAnnotationView.pinColor = MKPinAnnotationColorPurple;
    }
    return pinAnnotationView;
}

- (MKOverlayView *)mapView:(MKMapView *)mapView viewForOverlay:(id <MKOverlay>)overlay
{
    MKPolylineView *polylineView = [[MKPolylineView alloc] initWithPolyline:overlay];
    polylineView.strokeColor = [UIColor blueColor];
    polylineView.lineWidth = 5.0;
    
    return polylineView;
}

- (NSString *)archivePath
{
    NSString *documentsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    NSString *archivePath = [documentsDir stringByAppendingPathComponent:@"lastRoute.archive"];
    return archivePath;
}



@end


