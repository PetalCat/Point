enum MapProviderType {
  google('Google Maps', 'The maps you know. Works out of the box.'),
  osm('OpenStreetMap', 'No tracking. No data collection. Community-powered.'),
  mapbox('Mapbox', 'Beautiful maps. Bring your own API key.'),
  selfHosted('Custom Tile Server', 'For advanced users running their own tiles.');

  final String label;
  final String description;
  const MapProviderType(this.label, this.description);
}
