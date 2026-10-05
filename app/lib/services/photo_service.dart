import 'dart:typed_data';

import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:image_picker/image_picker.dart';

import '../config.dart';
import '../models/kind.dart';

class PickedPhoto {
  const PickedPhoto({required this.path, required this.bytes});

  /// Temporary file written by the picker; copied into app storage only if the user saves.
  final String path;
  final Uint8List bytes;
}

/// What the free on-device labeller sees. Used to route "detect automatically" and to warn
/// before a paid identification when the photo shows no plant or animal at all.
class PhotoHint {
  const PhotoHint({required this.kind, required this.confidence, required this.labels, required this.looksUnrelated});

  final Kind? kind;
  final double confidence;
  final List<Map<String, Object>> labels;

  /// True when the labeller is confident the photo shows something else entirely.
  final bool looksUnrelated;

  Map<String, dynamic> toJson() => {
        'category': kind?.name ?? 'other',
        'confidence': double.parse(confidence.toStringAsFixed(3)),
        'labels': labels,
      };
}

class PhotoService {
  final _picker = ImagePicker();

  /// Takes or chooses a photo, already resized on the phone so uploads stay small on 3G.
  Future<PickedPhoto?> pick({required bool camera}) async {
    final file = await _picker.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: AppConfig.photoMaxEdge,
      maxHeight: AppConfig.photoMaxEdge,
      imageQuality: AppConfig.photoQuality,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    return PickedPhoto(path: file.path, bytes: await file.readAsBytes());
  }

  /// Labels the photo on the device. Free and offline; never throws.
  Future<PhotoHint?> hint(String path) async {
    final labeler = ImageLabeler(options: ImageLabelerOptions(confidenceThreshold: 0.3));
    try {
      final labels = await labeler.processImage(InputImage.fromFilePath(path));
      return hintFromLabels([for (final l in labels) (label: l.label, confidence: l.confidence)]);
    } catch (_) {
      return null;
    } finally {
      await labeler.close();
    }
  }
}

const _plantLabels = {'plant', 'flower', 'houseplant', 'flowerpot', 'leaf', 'tree', 'petal', 'moss', 'cactus', 'garden'};

/// Turns on-device labels into a routing hint. Pure function, unit-tested.
PhotoHint hintFromLabels(List<({String label, double confidence})> labels) {
  final scores = <Kind, double>{};
  void bump(Kind k, double c) => scores[k] = (scores[k] ?? 0) < c ? c : scores[k]!;
  var strongestOther = 0.0;
  for (final l in labels) {
    final name = l.label.toLowerCase();
    if (_plantLabels.contains(name)) {
      bump(Kind.plant, l.confidence);
    } else if (name == 'cat') {
      bump(Kind.cat, l.confidence);
    } else if (name == 'dog') {
      bump(Kind.dog, l.confidence);
    } else if (name == 'bird') {
      bump(Kind.bird, l.confidence);
    } else if (l.confidence > strongestOther) {
      strongestOther = l.confidence;
    }
  }
  Kind? best;
  var bestScore = 0.0;
  scores.forEach((k, v) {
    if (v > bestScore) {
      best = k;
      bestScore = v;
    }
  });
  return PhotoHint(
    kind: best,
    confidence: bestScore,
    labels: [
      for (final l in labels.take(10)) {'label': l.label, 'confidence': double.parse(l.confidence.toStringAsFixed(3))},
    ],
    looksUnrelated: best == null && strongestOther >= 0.7,
  );
}
