class AnalyzeModel {
  String task;
  List<String> filesToChange;
  List<String> filesInProjectDir;

  AnalyzeModel({
    required this.task,
    required this.filesToChange,
    required this.filesInProjectDir,
  });
}
