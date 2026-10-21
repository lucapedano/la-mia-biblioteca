class Book {
  final String id;
  final String title;
  final String author;
  final String theme;
  final int? year;
  final String color;
  final int? pages;
  final String status; // to_read | reading | read
  final String? plot;
  final String? notes;
  final String? location;
  final String? coverUrl;
  final String? isbn;
  final String? createdAt;
  final String? updatedAt;
  final String? cloudCoverPath;

  Book({
    required this.id,
    required this.title,
    required this.author,
    required this.theme,
    this.year,
    this.color = '#8D6E63',
    this.pages,
    this.status = 'to_read',
    this.plot,
    this.notes,
    this.location,
    this.coverUrl,
    this.isbn,
    this.createdAt,
    this.updatedAt,
    this.cloudCoverPath,
  });

  factory Book.fromJson(Map<String, dynamic> j) {
    return Book(
      id: (j['id'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      author: (j['author'] ?? '').toString(),
      theme: (j['theme'] ?? '').toString(),
      year: j['year'] is int
          ? j['year'] as int
          : int.tryParse('${j['year'] ?? ''}'),
      color: (j['color'] ?? '#8D6E63').toString(),
      pages: j['pages'] is int
          ? j['pages'] as int
          : int.tryParse('${j['pages'] ?? ''}'),
      status: (j['status'] ?? 'to_read').toString(),
      plot: j['plot']?.toString(),
      notes: j['notes']?.toString(),
      location: j['location']?.toString(),
      coverUrl: j['cover_url']?.toString(),
      isbn: j['isbn']?.toString(),
      createdAt: j['created_at']?.toString(),
      updatedAt: j['updated_at']?.toString(),
      cloudCoverPath: j['cloud_cover_path']?.toString(),
    );
  }

  /// Payload for create/update (matches BookBase on the backend).
  Map<String, dynamic> toPayload() => {
        'title': title,
        'author': author,
        'theme': theme,
        if (year != null) 'year': year,
        'color': color,
        if (pages != null) 'pages': pages,
        'status': status,
        if (plot != null) 'plot': plot,
        if (notes != null) 'notes': notes,
        if (location != null) 'location': location,
        if (coverUrl != null) 'cover_url': coverUrl,
        if (isbn != null) 'isbn': isbn,
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        ...toPayload(),
        'created_at': createdAt,
        'updated_at': updatedAt,
        'cloud_cover_path': cloudCoverPath,
      };
}

const Map<String, String> kStatusLabels = {
  'to_read': 'Da leggere',
  'reading': 'In corso',
  'read': 'Letto',
};
