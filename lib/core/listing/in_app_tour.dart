import 'dart:convert';

/// جولة داخلية من صور الإعلان + نقاط تفاعل — تُحفظ في `listing_guidance.in_app_tour`.
class InAppTourHotspot {
  const InAppTourHotspot({
    required this.label,
    this.note = '',
    this.targetScene = 0,
    this.nx = 0.5,
    this.ny = 0.5,
  });

  final String label;
  final String note;
  final int targetScene;
  final double nx;
  final double ny;

  Map<String, dynamic> toJson() => {
        'label': label,
        'note': note,
        'target': targetScene,
        'nx': nx,
        'ny': ny,
      };

  static InAppTourHotspot fromJson(Map<String, dynamic> m) {
    return InAppTourHotspot(
      label: (m['label'] ?? '').toString(),
      note: (m['note'] ?? '').toString(),
      targetScene: (m['target'] as num?)?.toInt() ?? 0,
      nx: (m['nx'] as num?)?.toDouble() ?? 0.5,
      ny: (m['ny'] as num?)?.toDouble() ?? 0.5,
    );
  }
}

class InAppTourScene {
  const InAppTourScene({
    required this.imageRef,
    this.title = '',
    this.hotspots = const [],
  });

  final String imageRef;
  final String title;
  final List<InAppTourHotspot> hotspots;

  InAppTourScene copyWith({
    String? imageRef,
    String? title,
    List<InAppTourHotspot>? hotspots,
  }) {
    return InAppTourScene(
      imageRef: imageRef ?? this.imageRef,
      title: title ?? this.title,
      hotspots: hotspots ?? this.hotspots,
    );
  }

  Map<String, dynamic> toJson() => {
        'image': imageRef,
        'title': title,
        'hotspots': [for (final h in hotspots) h.toJson()],
      };

  static InAppTourScene fromJson(Map<String, dynamic> m) {
    final raw = m['hotspots'];
    final spots = <InAppTourHotspot>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          spots.add(InAppTourHotspot.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return InAppTourScene(
      imageRef: (m['image'] ?? m['path'] ?? '').toString(),
      title: (m['title'] ?? '').toString(),
      hotspots: spots,
    );
  }
}

class InAppTour {
  const InAppTour({
    this.scenes = const [],
    this.engine = 'in_app_walk',
  });

  final List<InAppTourScene> scenes;
  /// جولة داخلية تفاعلية داخل المنصة — ليست محرك Matterport سحابي.
  final String engine;

  bool get isEmpty => scenes.isEmpty;
  bool get isNotEmpty => scenes.isNotEmpty;

  InAppTour remapped(List<String> paths) {
    return InAppTour(
      engine: engine,
      scenes: [
        for (final s in scenes)
          InAppTourScene(
            imageRef: () {
              final i = int.tryParse(s.imageRef);
              if (i != null && i >= 0 && i < paths.length) return paths[i];
              return s.imageRef;
            }(),
            title: s.title,
            hotspots: s.hotspots,
          ),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
        'v': 2,
        'engine': engine,
        'scenes': [for (final s in scenes) s.toJson()],
      };

  static InAppTour? fromGuidance(Map<String, dynamic>? guidance) {
    if (guidance == null) return null;
    return fromRaw(guidance['in_app_tour']);
  }

  static InAppTour? fromRaw(dynamic raw) {
    if (raw == null) return null;
    Map<String, dynamic>? map;
    if (raw is Map) {
      map = Map<String, dynamic>.from(raw);
    } else if (raw is String && raw.trim().isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is Map) map = Map<String, dynamic>.from(d);
      } catch (_) {
        return null;
      }
    }
    if (map == null) return null;
    final scenesRaw = map['scenes'];
    if (scenesRaw is! List || scenesRaw.isEmpty) return null;
    final scenes = <InAppTourScene>[];
    for (final e in scenesRaw) {
      if (e is Map) {
        final s = InAppTourScene.fromJson(Map<String, dynamic>.from(e));
        if (s.imageRef.trim().isNotEmpty) scenes.add(s);
      }
    }
    if (scenes.isEmpty) return null;
    final engine = (map['engine'] ?? 'in_app_walk').toString().trim();
    return InAppTour(
      scenes: scenes,
      engine: engine.isEmpty ? 'in_app_walk' : engine,
    );
  }

  static InAppTour fromImageRefs(List<String> refs) {
    return InAppTour(
      scenes: [
        for (final r in refs)
          if (r.trim().isNotEmpty) InAppTourScene(imageRef: r.trim()),
      ],
    );
  }
}
