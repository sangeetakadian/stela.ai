import 'package:flutter/material.dart';
import 'package:stela_app/services/code_execution_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/quiz_model.dart';

/// A simple code editor widget for coding questions in quizzes
class CodeEditorWidget extends StatefulWidget {
  final ProgrammingLanguage language;
  final String? initialCode;
  final Function(String) onCodeChanged;
  final bool readOnly;

  const CodeEditorWidget({
    Key? key,
    required this.language,
    this.initialCode,
    required this.onCodeChanged,
    this.readOnly = false,
  }) : super(key: key);

  @override
  State<CodeEditorWidget> createState() => _CodeEditorWidgetState();
}

class _CodeEditorWidgetState extends State<CodeEditorWidget> {
  late TextEditingController _controller;
  int _currentLine = 1;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialCode ?? '');
    _controller.addListener(_updateLineCount);
    
    // Calculate initial line count without triggering callback
    final lines = _controller.text.split('\n').length;
    _currentLine = lines;
  }

  @override
  void didUpdateWidget(covariant CodeEditorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldInitial = oldWidget.initialCode ?? '';
    final newInitial = widget.initialCode ?? '';

    // Only update the controller if the parent changed initialCode AND the user
    // hasn't modified the text away from the previous initialCode.
    if (newInitial != oldInitial && _controller.text == oldInitial) {
      _controller.value = _controller.value.copyWith(
        text: newInitial,
        selection: TextSelection.collapsed(offset: newInitial.length),
        composing: TextRange.empty,
      );
    }
  }

  void _updateLineCount() {
    final lines = _controller.text.split('\n').length;
    if (_currentLine != lines) {
      setState(() {
        _currentLine = lines;
      });
    }
    // Only call onCodeChanged if the widget is still mounted
    if (mounted) {
      widget.onCodeChanged(_controller.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with language indicator
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Color(0xFF2D2D30),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _getLanguageIcon(),
                  size: 16,
                  color: Colors.white70,
                ),
                SizedBox(width: 8),
                Text(
                  getLanguageDisplayName(widget.language),
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Spacer(),
                if (!widget.readOnly)
                  IconButton(
                    icon: Icon(Icons.content_copy, size: 16),
                    color: Colors.white70,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _controller.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Code copied to clipboard'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                  ),
              ],
            ),
          ),
          
          // Code editor area
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Line numbers
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  color: Color(0xFF252526),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: List.generate(
                        _currentLine,
                        (index) => Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                            fontFamily: 'monospace',
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                
                // Code input area
                Expanded(
                  child: Container(
                    color: Colors.black,
                    child: TextField(
                      controller: _controller,
                      readOnly: widget.readOnly,
                      maxLines: null,
                      expands: true,
                      textAlign: TextAlign.start,
                      textAlignVertical: TextAlignVertical.top,
                      cursorColor: Colors.white,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontFamily: 'monospace',
                        height: 1.5,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        filled: true,
                        fillColor: Colors.black,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        hintText: widget.readOnly ? '' : 'Write code here...',
                        hintStyle: TextStyle(
                          color: Colors.grey.shade500,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getLanguageIcon() {
    switch (widget.language) {
      case ProgrammingLanguage.python:
        return Icons.code;
      case ProgrammingLanguage.java:
        return Icons.coffee;
      case ProgrammingLanguage.cpp:
        return Icons.code_outlined;
      case ProgrammingLanguage.javascript:
        return Icons.javascript;
      case ProgrammingLanguage.dart:
        return Icons.flutter_dash;
    }
  }
}

/// A simulated code runner for local testing purposes.
/// Since a real full coding IDE requires a backend (e.g., Judge0 or custom server), 
/// this simulation provides feedback by comparing logic with the solution code.
class SimulatedCodeRunner {
  static String _defaultExecUrl() {
    const fromDefine = String.fromEnvironment('CODE_EXEC_ENDPOINT', defaultValue: '');
    if (fromDefine.trim().isNotEmpty) return fromDefine.trim();

    // Local dev convenience: if the Flutter app is running on localhost (web),
    // prefer a local backend that supports multiple languages.
    if (kIsWeb) {
      final host = Uri.base.host.toLowerCase();
      if (host == 'localhost' || host == '127.0.0.1') {
        return 'http://localhost:8080/execute';
      }
    }

    return '';
  }

  static Future<List<TestCaseExecutionResult>> runTests({
    required String code,
    required List<dynamic> testCasesData,
    required ProgrammingLanguage language,
    ProgrammingLanguage? solutionLanguage,
    String? solutionCode,
    bool skipDelay = false,
  }) async {
    // Simulate runtime delay
    if (!skipDelay) {
      await Future.delayed(Duration(seconds: 1, milliseconds: 500));
    }

    List<TestCaseExecutionResult> results = [];

    final execUrl = _defaultExecUrl();

    // Strict grading: execute code and compare outputs.
    // Expected output comes from:
    // 1) test case expectedOutput (preferred), else
    // 2) execution of faculty-provided solutionCode for that test input.
    // If execution fails/unavailable, the test case fails (no heuristic auto-pass).
    final facultySolutionLanguage = solutionLanguage ?? language;

    for (final tcData in testCasesData) {
      final input = (tcData['input'] ?? '').toString();
      final expectedFromCase = (tcData['expectedOutput'] ?? tcData['output'] ?? '').toString();

      if (code.trim().isEmpty) {
        results.add(TestCaseExecutionResult(
          input: input,
          expectedOutput: expectedFromCase,
          actualOutput: '',
          isPassed: false,
          error: 'Empty source code',
        ));
        continue;
      }

      String expected = expectedFromCase;
      if (expected.trim().isEmpty) {
        if (solutionCode != null && solutionCode.trim().isNotEmpty) {
          try {
            expected = await _executeRemote(
              code: solutionCode,
              stdin: input,
              url: execUrl,
              language: facultySolutionLanguage,
            );
          } catch (e) {
            results.add(TestCaseExecutionResult(
              input: input,
              expectedOutput: '',
              actualOutput: '',
              isPassed: false,
              error: 'Failed to compute expected output from solution: $e',
            ));
            continue;
          }
        } else {
          results.add(TestCaseExecutionResult(
            input: input,
            expectedOutput: '',
            actualOutput: '',
            isPassed: false,
            error: 'No expected output provided and no solution code available.',
          ));
          continue;
        }
      }

      try {
        final actual = await _executeRemote(
          code: code,
          stdin: input,
          url: execUrl,
          language: language,
        );

        final normExpected = _normalizeOutput(expected);
        final normActual = _normalizeOutput(actual);
        final isPassed = normExpected == normActual;

        results.add(TestCaseExecutionResult(
          input: input,
          expectedOutput: expected,
          actualOutput: actual,
          isPassed: isPassed,
          error: isPassed ? null : 'Output mismatch',
        ));
      } catch (e) {
        results.add(TestCaseExecutionResult(
          input: input,
          expectedOutput: expected,
          actualOutput: '',
          isPassed: false,
          error: 'Execution failed: $e',
        ));
      }
    }

    return results;
  }

  static String _normalizeOutput(String s) {
    // Normalize line endings and trailing whitespace/newlines.
    final lines = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final trimmedLines = lines.map((l) => l.trimRight()).toList();
    // Remove trailing empty lines
    while (trimmedLines.isNotEmpty && trimmedLines.last.trim().isEmpty) {
      trimmedLines.removeLast();
    }
    return trimmedLines.join('\n');
  }

  static String _wrapPythonWithStdin({required String code, required String stdin}) {
    // NOTE: This is intended for controlled educational execution environments.
    // The remote execution service must sandbox untrusted code.
    final safeInput = stdin.replaceAll("'''", "''");
    return "import sys, io\n"
        "sys.stdin = io.StringIO(r'''$safeInput''')\n"
        "\n"
        "# --- user code start ---\n"
        "$code\n"
        "# --- user code end ---\n";
  }

  static Future<String> _executeRemote({
    required String code,
    required String stdin,
    required String url,
    required ProgrammingLanguage language,
  }) async {
    // Compatibility note:
    // - Some endpoints accept only {code, language}.
    // - Our grading backend should accept {code, language, input}.
    // For Python, we also embed stdin into code to work with endpoints that don't support input.
    final languageStr = _mapLanguage(language);
    final payload = <String, dynamic>{
      'code': language == ProgrammingLanguage.python ? _wrapPythonWithStdin(code: code, stdin: stdin) : code,
      'language': languageStr,
    };

    // Common field name used by many execution services.
    if (stdin.isNotEmpty) {
      payload['input'] = stdin;
    }
    const maxAttempts = 3;
    var lastError = 'Execution failed. Please try again.';

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final resp = await http
            .post(Uri.parse(url), headers: await codeExecutionHeaders(), body: jsonEncode(payload))
            .timeout(const Duration(seconds: 25));

        Map<String, dynamic>? decoded;
        try {
          final parsed = jsonDecode(resp.body);
          if (parsed is Map<String, dynamic>) {
            decoded = parsed;
          }
        } catch (_) {
          // Ignore non-JSON body and fall back to generic messaging.
        }

        final retryableStatus = resp.statusCode == 429 || resp.statusCode == 502 || resp.statusCode == 503 || resp.statusCode == 504;

        if (retryableStatus && attempt < maxAttempts) {
          final retryAfter = (decoded?['retryAfterSeconds'] as num?)?.toInt() ?? attempt;
          await Future.delayed(Duration(seconds: retryAfter.clamp(1, 4)));
          continue;
        }

        if (resp.statusCode != 200) {
          final backendError = (decoded?['error'] ?? decoded?['stderr'] ?? '').toString().trim();
          if (backendError.isNotEmpty) {
            throw Exception(backendError);
          }
          throw Exception('Execution failed (HTTP ${resp.statusCode})');
        }

        if (decoded != null) {
          // Prefer result for compatibility with existing code.
          final result = decoded['result'] ?? decoded['stdout'];
          final error = decoded['error'] ?? decoded['stderr'];
          if (error != null && error.toString().trim().isNotEmpty && (result == null || result.toString().trim().isEmpty)) {
            throw Exception(error.toString());
          }

          final resultStr = result?.toString() ?? '';
          // Some older Python-only endpoints return Python parse errors inside `result`
          // (and don't populate `error`). If the student selected a non-Python language,
          // surface a clearer configuration error.
          if (language != ProgrammingLanguage.python && _looksLikePythonOnlyError(resultStr)) {
            throw Exception(
              'Execution endpoint appears to be Python-only. '
              'Configure CODE_EXEC_ENDPOINT to a multi-language /execute backend.',
            );
          }

          return resultStr;
        }

        return '';
      } catch (e) {
        lastError = e.toString();
        if (attempt < maxAttempts) {
          await Future.delayed(Duration(milliseconds: 300 * attempt));
          continue;
        }
      }
    }

    throw Exception(
      'The server is busy right now. Please wait a moment and try again. '
      'Details: $lastError',
    );
  }

  static String _mapLanguage(ProgrammingLanguage language) {
    switch (language) {
      case ProgrammingLanguage.python:
        return 'python';
      case ProgrammingLanguage.java:
        return 'java';
      case ProgrammingLanguage.cpp:
        return 'cpp';
      case ProgrammingLanguage.javascript:
        return 'javascript';
      case ProgrammingLanguage.dart:
        return 'dart';
    }
  }

  static bool _looksLikePythonOnlyError(String s) {
    final v = s.toLowerCase();
    return v.contains('traceback (most recent call last)') ||
        v.contains('syntaxerror') ||
        v.contains('invalid syntax') ||
        v.contains("nameerror") ||
        v.contains("indentationerror") ||
        v.contains("<string>, line");
  }

  // NOTE: Heuristic grading intentionally removed.
}

/// A class representing a test case result after simulation or execution
class TestCaseExecutionResult {
  final String input;
  final String expectedOutput;
  final String actualOutput;
  final bool isPassed;
  final String? error;

  TestCaseExecutionResult({
    required this.input,
    required this.expectedOutput,
    required this.actualOutput,
    required this.isPassed,
    this.error,
  });
}

/// Dialog to display the execution results of test cases
class TestResultsDialog extends StatelessWidget {
  final List<TestCaseExecutionResult> results;
  final ProgrammingLanguage language;

  const TestResultsDialog({
    Key? key,
    required this.results,
    required this.language,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    int totalPass = results.where((r) => r.isPassed).length;
    int totalCount = results.length;
    bool allPassed = totalPass == totalCount;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            allPassed ? Icons.check_circle : Icons.error,
            color: allPassed ? Colors.green : Colors.red,
          ),
          SizedBox(width: 12),
          Text('Test Results: $totalPass/$totalCount Passed'),
        ],
      ),
      content: Container(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: results.asMap().entries.map((entry) {
              final result = entry.value;
              final index = entry.key;
              
              return Container(
                margin: EdgeInsets.only(bottom: 12),
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: result.isPassed ? Colors.green.shade50 : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: result.isPassed ? Colors.green.shade200 : Colors.red.shade200,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Test Case ${index + 1}',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Spacer(),
                        Icon(
                          result.isPassed ? Icons.check : Icons.close,
                          size: 16,
                          color: result.isPassed ? Colors.green : Colors.red,
                        ),
                        SizedBox(width: 4),
                        Text(
                          result.isPassed ? 'Passed' : 'Failed',
                          style: TextStyle(
                            color: result.isPassed ? Colors.green[700] : Colors.red[700],
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    Divider(),
                    _buildResultDetail('Input', result.input),
                    _buildResultDetail('Expected Output', result.expectedOutput),
                    _buildResultDetail('Actual Output', result.actualOutput, isActual: true, isError: !result.isPassed),
                    if (result.error != null)
                      _buildResultDetail('Error Message', result.error!, isError: true),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close'),
        ),
      ],
    );
  }

  Widget _buildResultDetail(String label, String content, {bool isActual = false, bool isError = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isError ? Colors.red[100]!.withOpacity(0.3) : Colors.white.withOpacity(0.5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              content,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: isError ? Colors.red[900] : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget to display test cases for a coding question
class TestCasesDisplay extends StatelessWidget {
  final List<TestCase> testCases;

  const TestCasesDisplay({
    Key? key,
    required this.testCases,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final visibleTestCases = testCases.where((tc) => !tc.isHidden).toList();

    if (visibleTestCases.isEmpty) {
      return SizedBox.shrink();
    }

    return Card(
      margin: EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sample Test Cases',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 12),
            ...visibleTestCases.asMap().entries.map((entry) {
              final index = entry.key;
              final testCase = entry.value;
              return Container(
                margin: EdgeInsets.only(bottom: 12),
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Test Case ${index + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                    if (testCase.description != null) ...[
                      SizedBox(height: 4),
                      Text(
                        testCase.description!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                    SizedBox(height: 8),
                    _buildTestCaseSection('Input', testCase.input),
                    SizedBox(height: 6),
                    _buildTestCaseSection('Expected Output', testCase.expectedOutput),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildTestCaseSection(String label, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        ),
        SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Text(
            content,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}
