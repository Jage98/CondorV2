//
//  ContentView.swift
//  CondorV2
// This is only one file made public from my private project for showcasing SwiftUI code
//
//


import SwiftUI
import CoreData
import CoreLocation
import CloudKit
import MapKit

struct ContentView: View {
    @ObservedObject var playedRound: PlayedRoundEntity
    @Environment(\.managedObjectContext) private var context
    @Environment(\.presentationMode) var presentationMode
    @State private var currentHoleIndex = 0
    @State private var holes: [HoleEntity] = []
    @State private var strokeCount: Int = 0
    @ObservedObject var locationManager = LocationManager.shared
    @State private var showingEndRoundAlert = false
    @State private var shouldNavigateToDetailView = false
    @State private var regionSet = false
    @State private var region = MKCoordinateRegion()
    @State private var selectedSpot: CLLocationCoordinate2D?
    @State private var userLocation = CLLocationCoordinate2D()
    @State private var flagLocation = CLLocationCoordinate2D()
    
    
    var body: some View {
        VStack {
            if let hole = holes[safe: currentHoleIndex] {
                if locationManager.currentLocation != nil {
                    // Map View
                    MapView(
                        region: $region,
                        regionSet: $regionSet,
                        userLocation: $userLocation,
                        flagLocation: $flagLocation,
                        selectedSpot: $selectedSpot
                    )
                    .frame(height: 500)
                    
                    // Banner with navigation arrows and hole info
                    HStack {
                        // Previous Hole Button
                        Button(action: {
                            if currentHoleIndex > 0 {
                                currentHoleIndex -= 1
                                strokeCount = 0
                                regionSet = false
                                selectedSpot = nil // Reset selected spot
                            }
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.title)
                                .padding()
                        }
                        .disabled(currentHoleIndex == 0)
                        
                        Spacer()
                        
                        // Hole Info
                        VStack(alignment: .center) {
                            Text("Hole \(hole.number)")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("Par: \(hole.par)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            if let currentLocation = locationManager.currentLocation {
                                let flagDistance = currentLocation.distance(from: CLLocation(latitude: hole.flagLatitude, longitude: hole.flagLongitude))
                                Text("Distance: \(Int(flagDistance)) m")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        Spacer()
                        
                        // Next Hole Button
                        Button(action: {
                            if currentHoleIndex < holes.count - 1 {
                                currentHoleIndex += 1
                                strokeCount = 0
                                regionSet = false
                                selectedSpot = nil // Reset selected spot
                            }
                        }) {
                            Image(systemName: "chevron.right")
                                .font(.title)
                                .padding()
                        }
                        .disabled(currentHoleIndex == holes.count - 1)
                    }
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    
                    // Number Pad at the bottom
                    Spacer()
                    NumberPadView(strokeCount: $strokeCount)
                } else {
                    Text("Fetching location...").foregroundColor(.white)
                }
            } else {
                Text("No holes available").foregroundColor(.white)
                Button("Start Hole \(currentHoleIndex + 1)") {
                    createNewHole()
                }
                .padding()
            }
        }
        .background(Color(hex: "1C1C1C").edgesIgnoringSafeArea(.all))
        .navigationBarTitle(playedRound.courseName ?? "Course", displayMode: .inline)
        .navigationBarItems(
            trailing: Button(action: {
                showingEndRoundAlert = true
            }) {
                Text("Finish Round")
                    .foregroundColor(.red)
            }
        )
        .alert(isPresented: $showingEndRoundAlert) {
            Alert(
                title: Text("Finish Round"),
                message: Text("Do you want to finish the round?"),
                primaryButton: .destructive(Text("Finish")) {
                    endRound()
                    shouldNavigateToDetailView = true
                },
                secondaryButton: .cancel()
            )
        }
        .background(
            NavigationLink(destination: RoundDetailView(round: playedRound), isActive: $shouldNavigateToDetailView) {
                EmptyView()
            }
        )
        .onAppear {
                    fetchHoles()
                    locationManager.startLocationUpdates()
                    updateLocations()
                    regionSet = false // Reset regionSet when the view appears
                }
        .onDisappear {
            locationManager.stopUpdatingHeading()
        }
        .onChange(of: currentHoleIndex) { _ in
                    updateLocations()
                    regionSet = false // Reset regionSet at the start of a new hole
                    selectedSpot = nil // Reset selected spot
                }
                .onReceive(locationManager.$currentLocation) { _ in
                    updateLocations()
                }
    }
    
    private func updateLocations() {
            if let hole = holes[safe: currentHoleIndex],
               let currentLocation = locationManager.currentLocation {
                userLocation = currentLocation.coordinate
                flagLocation = CLLocationCoordinate2D(latitude: hole.flagLatitude, longitude: hole.flagLongitude)
                
                if !regionSet {
                    setRegion()
                }
            }
        }

    private func fetchHoles() {
        let request: NSFetchRequest<HoleEntity> = HoleEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \HoleEntity.number, ascending: true)]
        request.predicate = NSPredicate(format: "round == %@", playedRound)

        do {
            holes = try context.fetch(request)
            print("Fetched holes count: \(holes.count)")
        } catch {
            print("Failed to fetch holes: \(error)")
        }
    }
    
    private func endRound() {
        playedRound.completed = true
        do {
            try context.save()
            print("Round completed and saved successfully")
        } catch {
            print("Error saving the round end: \(error)")
        }
    }

    private func createNewHole() {
        let newHole = HoleEntity(context: context)
        newHole.number = Int16(currentHoleIndex + 1)
        newHole.round = playedRound
        saveContext()
    }

    private func recordShot(for hole: HoleEntity, latitude: Double, longitude: Double) {
        let newShot = ShotEntity(context: context)
        newShot.hole = hole
        newShot.timestamp = Date()
        newShot.latitude = latitude
        newShot.longitude = longitude
        saveContext()
        print("Shot recorded with location. Context saved.")
        fetchHoles()
    }
    
    private func deleteLastShot(for hole: HoleEntity) {
        let request: NSFetchRequest<ShotEntity> = ShotEntity.fetchRequest()
        request.predicate = NSPredicate(format: "hole == %@", hole)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ShotEntity.timestamp, ascending: false)]
        request.fetchLimit = 1

        do {
            if let lastShot = try context.fetch(request).first {
                context.delete(lastShot)
                saveContext()
                print("Last shot deleted. Context saved.")
                fetchHoles()
            }
        } catch {
            print("Failed to delete last shot: \(error)")
        }
    }

    private func saveContext() {
        do {
            try context.save()
        } catch {
            print("Failed to save context: \(error)")
        }
    }
    private func setRegion() {
           let centerLatitude = (userLocation.latitude + flagLocation.latitude) / 2
           let centerLongitude = (userLocation.longitude + flagLocation.longitude) / 2
           let center = CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude)

           let latitudeDelta = abs(userLocation.latitude - flagLocation.latitude) * 2.5
           let longitudeDelta = abs(userLocation.longitude - flagLocation.longitude) * 2.5

           region = MKCoordinateRegion(
               center: center,
               span: MKCoordinateSpan(latitudeDelta: max(latitudeDelta, 0.005), longitudeDelta: max(longitudeDelta, 0.005))
           )
           regionSet = true
       }
}




struct MapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
        @Binding var regionSet: Bool
        @Binding var userLocation: CLLocationCoordinate2D
        @Binding var flagLocation: CLLocationCoordinate2D
        @Binding var selectedSpot: CLLocationCoordinate2D?
    
    func makeUIView(context: Context) -> MKMapView {
            let mapView = MKMapView()
            mapView.delegate = context.coordinator
            mapView.showsUserLocation = true
            mapView.mapType = .hybridFlyover
            
            let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
            mapView.addGestureRecognizer(tapGesture)
            
            return mapView
        }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        // Only set the region if regionSet is false
        if !regionSet {
            // Compute the region to include both userLocation and flagLocation
            let centerLatitude = (userLocation.latitude + flagLocation.latitude) / 2
            let centerLongitude = (userLocation.longitude + flagLocation.longitude) / 2
            let center = CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude)
    
            let latitudeDelta = abs(userLocation.latitude - flagLocation.latitude) * 2.5
            let longitudeDelta = abs(userLocation.longitude - flagLocation.longitude) * 2.5
    
            let newRegion = MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: max(latitudeDelta, 0.005), longitudeDelta: max(longitudeDelta, 0.005))
            )
    
            uiView.setRegion(newRegion, animated: true)
            regionSet = true // Mark the region as set
        }
        
        // Remove existing annotations and overlays
        uiView.removeAnnotations(uiView.annotations.filter { !($0 is MKUserLocation) })
        uiView.removeOverlays(uiView.overlays)
        
        // Add flag annotation
        let flagAnnotation = MKPointAnnotation()
        flagAnnotation.coordinate = flagLocation
        flagAnnotation.title = "Flag"
        uiView.addAnnotation(flagAnnotation)
        
        // Draw line from user to flag
        let userToFlagLine = MKPolyline(coordinates: [userLocation, flagLocation], count: 2)
        uiView.addOverlay(userToFlagLine)
        
        // Add distance annotation at the midpoint between user and flag
        let userToFlagMidpoint = CLLocationCoordinate2D(
            latitude: (userLocation.latitude + flagLocation.latitude) / 2,
            longitude: (userLocation.longitude + flagLocation.longitude) / 2
        )
        let userToFlagDistance = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude).distance(from: CLLocation(latitude: flagLocation.latitude, longitude: flagLocation.longitude))
        let userToFlagDistanceAnnotation = DistanceAnnotation(coordinate: userToFlagMidpoint, title: "\(Int(userToFlagDistance)) m")
        uiView.addAnnotation(userToFlagDistanceAnnotation)
        
        // If there's a selected spot, draw lines and annotations
        if let selectedSpot = selectedSpot {
            // Draw line from user to selected spot
            let userToSpotLine = MKPolyline(coordinates: [userLocation, selectedSpot], count: 2)
            uiView.addOverlay(userToSpotLine)
            
            // Draw line from selected spot to flag
            let spotToFlagLine = MKPolyline(coordinates: [selectedSpot, flagLocation], count: 2)
            uiView.addOverlay(spotToFlagLine)
            
            // Add annotation for selected spot
            let spotAnnotation = MKPointAnnotation()
            spotAnnotation.coordinate = selectedSpot
            spotAnnotation.title = "Selected Spot"
            uiView.addAnnotation(spotAnnotation)
            
            // Distance from user to selected spot
            let userToSpotDistance = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude).distance(from: CLLocation(latitude: selectedSpot.latitude, longitude: selectedSpot.longitude))
            let userToSpotMidpoint = CLLocationCoordinate2D(
                latitude: (userLocation.latitude + selectedSpot.latitude) / 2,
                longitude: (userLocation.longitude + selectedSpot.longitude) / 2
            )
            let userToSpotDistanceAnnotation = DistanceAnnotation(coordinate: userToSpotMidpoint, title: "\(Int(userToSpotDistance)) m")
            uiView.addAnnotation(userToSpotDistanceAnnotation)
            
            // Distance from selected spot to flag
            let spotToFlagDistance = CLLocation(latitude: selectedSpot.latitude, longitude: selectedSpot.longitude).distance(from: CLLocation(latitude: flagLocation.latitude, longitude: flagLocation.longitude))
            let spotToFlagMidpoint = CLLocationCoordinate2D(
                latitude: (selectedSpot.latitude + flagLocation.latitude) / 2,
                longitude: (selectedSpot.longitude + flagLocation.longitude) / 2
            )
            let spotToFlagDistanceAnnotation = DistanceAnnotation(coordinate: spotToFlagMidpoint, title: "\(Int(spotToFlagDistance)) m")
            uiView.addAnnotation(spotToFlagDistanceAnnotation)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView
        
        init(_ parent: MapView) {
            self.parent = parent
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let mapView = gesture.view as! MKMapView
            let tapPoint = gesture.location(in: mapView)
            let tapCoordinate = mapView.convert(tapPoint, toCoordinateFrom: mapView)
            
            parent.selectedSpot = tapCoordinate
        }
        
        // MKMapViewDelegate methods
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }
            
            if let distanceAnnotation = annotation as? DistanceAnnotation {
                let identifier = "DistanceAnnotation"
                var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                
                if annotationView == nil {
                    annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                    annotationView?.canShowCallout = false
                } else {
                    annotationView?.annotation = annotation
                }
                
                // Remove any existing subviews to prevent overlap
                annotationView?.subviews.forEach { $0.removeFromSuperview() }
                
                // Create a label to display the distance
                let label = UILabel()
                label.text = distanceAnnotation.title
                label.font = UIFont.boldSystemFont(ofSize: 14)
                label.textColor = UIColor.black // Set text color to black
                label.sizeToFit()
                label.backgroundColor = UIColor.white.withAlphaComponent(0.7)
                label.layer.cornerRadius = 5
                label.layer.masksToBounds = true
                annotationView?.addSubview(label)
                
                // Center the label
                label.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    label.centerXAnchor.constraint(equalTo: annotationView!.centerXAnchor),
                    label.centerYAnchor.constraint(equalTo: annotationView!.centerYAnchor)
                ])
                
                return annotationView
            } else {
                let identifier = "Marker"
                var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                
                if annotationView == nil {
                    annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                    annotationView?.canShowCallout = true
                } else {
                    annotationView?.annotation = annotation
                }
                
                if let markerAnnotationView = annotationView {
                    if annotation.title == "Flag" {
                        markerAnnotationView.markerTintColor = .red
                        markerAnnotationView.glyphImage = UIImage(systemName: "flag.fill")
                    } else if annotation.title == "Selected Spot" {
                        markerAnnotationView.markerTintColor = .blue
                        markerAnnotationView.glyphImage = UIImage(systemName: "mappin")
                    }
                }
                return annotationView
            }
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .yellow
                renderer.lineWidth = 3
                return renderer
            }
            return MKOverlayRenderer()
        }
    }
}

// Custom annotation class for distance labels
class DistanceAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    var title: String?
    
    init(coordinate: CLLocationCoordinate2D, title: String) {
        self.coordinate = coordinate
        self.title = title
    }
}

struct NumberPadView: View {
    @Binding var strokeCount: Int
    
    let numbers = [
        ["1", "2", "3", "4", "5"],
        ["6", "7", "8", "9", "0"]
    ]
    
    var body: some View {
        VStack(spacing: 10) {
            ForEach(numbers, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { number in
                        Button(action: {
                            if number == "0" && strokeCount == 0 {
                                return
                            }
                            strokeCount = (strokeCount * 10) + Int(number)!
                        }) {
                            Text(number)
                                .font(.title)
                                .frame(width: 60, height: 60)
                                .background(Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(5)
                        }
                    }
                }
            }
        }
        .padding()
    }
}
