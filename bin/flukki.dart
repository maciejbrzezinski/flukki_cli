import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:collection/collection.dart';
import 'package:dio/dio.dart';

import 'analyze_controller.dart';

// void main() {
//   OpenAI.apiKey = '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';
//   final message =
//       'Wciel się w rolę aplikacji, która rozmawia z API OpenAI. Twoim zadaniem jest wykonanie zadania programistycznego zapisanego tekstem w ludzki sposób dotyczącego napisanej we Flutterze. Znasz strukturę projektu, wszystkie klasy, metody i zależności, architekturę omawiającą warstwy aplikacji i jak te warstwy się ze sobą komunikują. Jakie komendy do chatu OpenAI powinny zostać wykonane i w jakiej koleności, aby zmodyfikować projekt aplikacji tak, aby zadanie można było uznać za zrobione?';
//   final response = AnalyzeController().test(message);
// }

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    print('Usage: flukki <api_key> "<task>"');
    exit(666);
  }
  final key = arguments[0];
  final projectDir = Directory.current;
  final project = projectDir.path;
  final task = arguments[1];
  final String? architecture = readFileToString('$project/flukki_architecture');

  print('Hello, I will work on this task:');
  print(task);
  print('');
  print('Starting project analyse...');
  print('');

  final filesInProjectDir = Directory(project)
      .listSync(recursive: true)
      .whereType<File>()
      .where((element) => element.path.endsWith('.dart'))
      .map((e) => e.path)
      .toList();

  print('Resolved: ${Platform.resolvedExecutable}');
  print('Executable: ${Platform.executable}');
  final dartSdk = Platform.resolvedExecutable
      .substring(0, Platform.resolvedExecutable.indexOf('/bin/dart'));

  final session = AnalysisContextCollection(
    includedPaths: filesInProjectDir,
    resourceProvider: PhysicalResourceProvider.INSTANCE,
    sdkPath: dartSdk,
  );
  List<FileLowLevelData> filesLowLevelData = [];
  for (final file in filesInProjectDir) {
    final element = session.contexts.first.currentSession.getParsedUnit(file)
        as ParsedUnitResult;
    final methods = element.unit.declarations
        .map((e) {
          if (e is ClassDeclaration) {
            return e.members
                .whereType<MethodDeclaration>()
                .map((e) => MethodLowLevelData(
                      e.name.toString(),
                      e.parameters?.parameters.map((param) {
                        SimpleFormalParameter parameter;
                        if (param is DefaultFormalParameter) {
                          parameter = param.parameter as SimpleFormalParameter;
                        } else {
                          parameter = param as SimpleFormalParameter;
                        }
                        return ParameterLowLevelData(
                            param.name.toString(), parameter.type.toString());
                      }).toList(),
                      (e.parent as ClassDeclaration).name.toString(),
                      e.toString(),
                    ));
          } else {
            return null;
          }
        })
        .toList()
        .fold(<MethodLowLevelData>[], (previousValue, element) {
          if (element != null) {
            return previousValue..addAll(element.toList());
          } else {
            return previousValue;
          }
        });
    final classes =
        element.unit.declarations.whereType<ClassDeclaration>().map((e) {
      final properties = List<String>.from(e.members
          .whereType<FieldDeclaration>()
          .map((e) => e.fields.variables.map((e) => e.toString()).toString())
          .toList());
      return ClassLowLevelData(e.name.toString(), methods, properties);
    }).toList();
    final enums = element.unit.declarations
        .whereType<EnumDeclaration>()
        .map((e) => EnumLowLevelData(e.name.toString(),
            e.constants.map((e) => e.name.toString()).toList()))
        .toList();
    final imports = element.unit.directives;
    final fileLowLevelData = FileLowLevelData(
      file,
      classes,
      imports.map((e) => e.toString()).toList(),
      enums,
      element.unit.toString(),
      project,
    );

    filesLowLevelData.add(fileLowLevelData);
  }

  final asMap = FilesLowLevel(filesLowLevelData).toMap();
  final files = await wrapApiCall(() async => await AnalyzeController()
      .whatFilesShouldBeChanged(architecture, asMap, task, key));
  print('I think these files may be affected by the task:');
  for (final file in files) {
    print(file.path);
  }
  print('');

  for (var fileChange in files) {
    final fileName = fileChange.path.split('/').last;
    final filePath = '$project${fileChange.path}';
    print('Looking on the $fileName...');

    try {
      final fileSpecifications = filesLowLevelData
          .firstWhereOrNull((element) => element.path == fileChange.path)
          ?.toMap(light: false);
      final thingsToChange = await wrapApiCall(() async =>
          await AnalyzeController().getThingsToChange(
              task, architecture, jsonEncode(fileSpecifications), key));
      if (thingsToChange.modifiedCode.isEmpty) {
        print('Did not found anything to change in $fileName');
        continue;
      } else {
        print('Methods that may have to be changed:');
        for (final change in thingsToChange.modifiedCode) {
          print('${change.name} -> ${change.changeDescription}');
        }
      }
      print('Updating $fileName...');
      final methods = filesLowLevelData
          .where((element) => element.path == fileChange.path)
          .map((e) => e.classes.fold(
              <MethodLowLevelData>[],
              (previousValue, element) =>
                  previousValue..addAll(element.methods)))
          .fold(
              <MethodLowLevelData>[],
              (previousValue, element) =>
                  previousValue..addAll(element)).toList();

      for (final thingToChange in thingsToChange.modifiedCode) {
        final currentMethod = methods
            .firstWhereOrNull((element) => element.name == thingToChange.name);

        if (currentMethod == null) continue;

        final properties = filesLowLevelData
            .where((element) => element.path == fileChange.path)
            .map((e) => e.classes.fold(
                <String>[],
                (previousValue, element) =>
                    previousValue..addAll(element.properties)))
            .fold(
                <String>[],
                (previousValue, element) =>
                    previousValue..addAll(element)).toList();

        final modifiedMethod = await wrapApiCall(() async =>
            await AnalyzeController().changeMethod(
                thingToChange.changeDescription,
                currentMethod.body,
                properties,
                task,
                key));

        if (modifiedMethod.newBody == null || modifiedMethod.newBody!.isEmpty) {
          continue;
        }
        final newSession = AnalysisContextCollection(
            includedPaths: [filePath],
            resourceProvider: PhysicalResourceProvider.INSTANCE);
        final currentBody = newSession.contexts.first.currentSession
            .getParsedUnit(filePath) as ParsedUnitResult;

        final newContent = currentBody.unit
            .toString()
            .replaceAll(currentMethod.body, modifiedMethod.newBody!);

        final file = File(filePath);
        file.writeAsStringSync(newContent);

        //todo: sprawdzić referencje do innych plików tej metody
      }
      print('Updated $fileName');
    } catch (e) {
      print(e);
    }
    try {
      print('Formatting $fileName...');
      await Process.run('dart', ['format', filePath]);
    } catch (e) {
      print('Could not format $fileName');
    }

    print('I\'m done with $fileName');
    print('');
  }
  print('Going home, bye');
  return;
}

String? readFileToString(String path) {
  try {
    return File(path).readAsStringSync();
  } catch (e) {
    return null;
  }
}

class FilesLowLevel {
  List<FileLowLevelData> files;

  FilesLowLevel(this.files);

  List<FileLowLevelData> findRelationsForFile(FileLowLevelData file) {
    return files
        .where((element) =>
            file.imports.any((import) => import.contains(element.name)))
        .toList();
  }

  String toMap({bool includeImports = false}) {
    return files.map((e) => e.toMap()).join('\n');
    // return {'f': files.map((e) => e.toMap(includeImports: false)).toList()};
  }
}

class FileLowLevelData {
  final String fullPath;
  late String path;
  late final String name;
  final List<ClassLowLevelData> classes;
  final List<String> imports;
  final List<EnumLowLevelData> enums;

  String body;

  FileLowLevelData(
    this.fullPath,
    this.classes,
    this.imports,
    this.enums,
    this.body,
    String projectRoot,
  ) {
    path = fullPath.replaceFirst(projectRoot, '');
    name = fullPath.split('/').last;
  }

  dynamic toMap({bool includeImports = false, bool light = true}) {
    if (light) {
      return '($path: ${classes.where((element) => !element.name.startsWith('_')).map((e) => e.toMap(light: light)).toList()})';
    }
    return {
      'path': path,
      'n': name,
      'classes': classes.map((e) => e.toMap()).toList(),
      if (includeImports) 'i': imports,
      if (enums.isNotEmpty) 'e': enums.map((e) => e.toMap()).toList(),
    };
  }
}

class EnumLowLevelData {
  final String name;
  final List<String> values;

  EnumLowLevelData(this.name, this.values);

  Map toMap() {
    return {'n': name, 'v': values};
  }
}

class ClassLowLevelData {
  final String name;
  late final List<MethodLowLevelData> methods;
  final List<String> properties;

  ClassLowLevelData(this.name, List<MethodLowLevelData> m, this.properties) {
    methods = m.where((element) => element.parentName == name).toList();
  }

  toMap({bool light = false}) {
    if (light) {
      return name;
    }
    // final filtereds = methods.where((element) =>
    //     !element.name.startsWith('_') &&
    //     element.name != 'toString' &&
    //     element.name != 'createState' &&
    //     element.name != 'build');
    return {
      'name': name,
      'methods': methods.map((e) => e.toMap()).toList()
      // if (filtereds.isNotEmpty) 'm': filtereds.map((e) => e.toMap()).toList()
    };
  }
}

class MethodLowLevelData {
  final String name;
  final String parentName;
  final List<ParameterLowLevelData>? parameters;
  final String body;

  MethodLowLevelData(
    this.name,
    this.parameters,
    this.parentName,
    this.body,
  );

  Map toMap() {
    // if (parameters == null || parameters!.isEmpty) return name;
    // return '$name(${parameters?.map((e) => e.toMap()).join(', ')})';
    return {
      'name': name,
      if (parameters != null && parameters!.isNotEmpty)
        'parameters': parameters?.map((e) => e.toMap()).toList()
    };
  }
}

class ParameterLowLevelData {
  final String name;
  final String type;

  ParameterLowLevelData(this.name, this.type);

  String toMap() {
    return '$type $name';
  }
}

Future<T> wrapApiCall<T>(Future<T> Function() apiCall) async {
  var result;
  try {
    result = await apiCall();
  } on DioException catch (e) {
    if (e.response?.statusCode == 403) {
      print(
          'Not enough credits to run the task. Contact Maciej: maciejbrzezinskibm@gmail.com');
    } else {
      print('Some error occurred: $e');
    }
    exit(2);
  } catch (e) {
    print('Some error occurred: $e');
    exit(1);
  }
  return result;
}
