import 'dart:convert';

import 'package:dio/dio.dart';

class AnalyzeController {
  Dio get dio {
    final dio = Dio();
    dio.options = BaseOptions(
      // baseUrl: 'http://localhost:8080',
      baseUrl: 'https://flukki-57n4nltafa-lm.a.run.app',
      headers: {'Content-Type': 'application/json'},
    );
    return dio;
  }

  Future<List<FileChange>> whatFilesShouldBeChanged(String? architecture,
      String projectStructure, String task, String key) async {
    final result = await dio.post('/thinkWhatFilesShouldBeChanged', data: {
      'architecture': architecture ?? '',
      'projectStructure': projectStructure,
      'task': task,
      'key': key,
    });

    final analyzeResults =
        List<dynamic>.from(jsonDecode(result.data)['result']['filesToChange']);
    return analyzeResults
        .map((e) => FileChange.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Modifications> getThingsToChange(String task, String? architecture,
      String fileStructure, String key) async {
    final result = await dio.post('/thinkAboutThingToChange', data: {
      'architecture': architecture ?? '',
      'fileStructure': fileStructure,
      'task': task,
      'key': key,
    });

    final analyzeResults = jsonDecode(result.data)['result'];
    return Modifications.fromJson(Map<String, dynamic>.from(analyzeResults));
  }

  Future<MethodModification> changeMethod(
    String changeDescription,
    String methodBody,
    List<String> properties,
    String task,
    String key,
  ) async {
    final result = await dio.post('/thinkAboutChange', data: {
      'changeDescription': changeDescription,
      'methodBody': methodBody,
      'properties': properties,
      'task': task,
      'key': key,
    });

    final analyzeResults = jsonDecode(result.data)['result'];
    return MethodModification.fromJson(
        Map<String, dynamic>.from(analyzeResults));
  }
}

class MethodModification {
  String? newBody;

  MethodModification(this.newBody);

  MethodModification.fromJson(Map<String, dynamic> json)
      : newBody = json['newBody'];
}

class Modifications {
  List<ModifyCode> modifiedCode;

  Modifications({required this.modifiedCode});

  Modifications.fromJson(Map<String, dynamic> json)
      : modifiedCode = List<ModifyCode>.from(
            json['modifiedCode'].map((e) => ModifyCode.fromJson(e)));
}

class AddCode {
  String newCodeDescription;
  String? parentClass;

  AddCode({required this.newCodeDescription, this.parentClass});
}

class ModifyCode {
  String name;
  String changeDescription;

  ModifyCode({required this.name, required this.changeDescription});

  ModifyCode.fromJson(Map<String, dynamic> json)
      : name = json['name'],
        changeDescription = json['changeDescription'];
}

enum FileChangeType {
  add,
  remove,
  modify;

  toJson() {
    switch (this) {
      case FileChangeType.add:
        return 'add';
      case FileChangeType.remove:
        return 'remove';
      case FileChangeType.modify:
        return 'modify';
    }
  }

  static FileChangeType fromJson(String json) {
    switch (json) {
      case 'add':
        return FileChangeType.add;
      case 'remove':
        return FileChangeType.remove;
      case 'modify':
        return FileChangeType.modify;
    }
    return FileChangeType.modify;
  }
}

class FileChange {
  FileChangeType type;
  String path;
  List<String> descriptions;

  FileChange(
      {required this.type, required this.path, required this.descriptions});

  FileChange.fromJson(Map<String, dynamic> json)
      : type = FileChangeType.fromJson(json['type']),
        path = json['path'],
        descriptions = json['content'] ?? [];
}
