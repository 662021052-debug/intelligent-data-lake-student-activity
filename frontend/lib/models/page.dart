class Page<T> {
  final List<T> items;
  final int total;
  final int skip;
  final int limit;

  Page({required this.items, required this.total, required this.skip, required this.limit});

  factory Page.fromJson(Map<String, dynamic> json, T Function(Map<String, dynamic>) fromJsonT) {
    return Page<T>(
      items: (json['items'] as List).map((e) => fromJsonT(e as Map<String, dynamic>)).toList(),
      total: json['total'] as int,
      skip: json['skip'] as int,
      limit: json['limit'] as int,
    );
  }
}
