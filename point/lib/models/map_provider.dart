enum MapProviderType {
  google('Google Maps', 'Default. Requires API key. Google privacy policy applies.'),
  osm('OpenStreetMap', 'Community-driven. No API key. No tracking. Most private.'),
  mapbox('Mapbox', 'High quality tiles. Requires API key. Better privacy than Google.'),
  selfHosted('Self-Hosted Tiles', 'Your own tile server. Complete control.');

  final String label;
  final String description;
  const MapProviderType(this.label, this.description);
}
