// kb.js — reads the knowledge base for tm-fix.sh.
//
// Runs under the JavaScript engine that ships with macOS:
//   osascript -l JavaScript kb.js COMMAND KB LOCAL_KB [ARG]
//
//   validate KB LOCAL_KB            check both files against the closed lists below
//   list     KB LOCAL_KB            one line per problem: id, evidence status, origin, title
//   match    KB LOCAL_KB SIGNALS    problems whose conditions all hold for SIGNALS
//   show     KB LOCAL_KB ID         one problem, formatted for reading
//
// KB is plugin/data/problems.json. LOCAL_KB is the person's own additions; it may be
// missing. Every line of output says which of the two files an entry came from
// (shipped or local), because the skill treats commands from the two differently.
// Nothing here writes a file or sends an Apple event.

ObjC.import('Foundation');
ObjC.import('stdlib');

// The closed lists. Adding a value here is a change to what the skill may do; update
// the skill's boundaries in the same change.
var CLASSES = ['direct', 'ask', 'user'];
var EVIDENCE = ['verified', 'reported', 'unverified'];
var OPS = ['equals', 'not_equals', 'gte', 'lte'];
var ID_PATTERN = /^[a-z0-9]+(-[a-z0-9]+)*$/;

function write(handle, text) {
  handle.writeData($(text).dataUsingEncoding($.NSUTF8StringEncoding));
}
function out(text) { write($.NSFileHandle.fileHandleWithStandardOutput, text + '\n'); }
function err(text) { write($.NSFileHandle.fileHandleWithStandardError, text + '\n'); }

function exists(path) {
  return $.NSFileManager.defaultManager.fileExistsAtPath(path);
}

function readText(path) {
  var s = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
  var text = ObjC.unwrap(s);
  if (typeof text !== 'string') { throw new Error('cannot read ' + path); }
  return text;
}

function readJson(path) {
  var text = readText(path);
  try {
    return JSON.parse(text);
  } catch (e) {
    throw new Error(path + ' is not valid JSON: ' + e.message);
  }
}

function isText(v) { return typeof v === 'string' && v.length > 0; }
function isList(v) { return Object.prototype.toString.call(v) === '[object Array]'; }

// Returns a list of messages; empty when the problems are well formed.
function checkProblems(problems, signals, takenIds, where) {
  var errors = [];
  var seen = {};
  if (!isList(problems)) { return [where + ': "problems" must be a list']; }
  problems.forEach(function (p, i) {
    var at = where + ': problem ' + (p && isText(p.id) ? p.id : '#' + (i + 1));
    if (!p || typeof p !== 'object') { errors.push(at + ' is not an object'); return; }
    if (!isText(p.id) || !ID_PATTERN.test(p.id)) { errors.push(at + ': "id" must be lower-case words joined by hyphens'); }
    else if (seen[p.id]) { errors.push(at + ': id used twice'); }
    else if (takenIds && takenIds[p.id]) { errors.push(at + ': id is already used by the shipped knowledge base'); }
    seen[p.id] = true;
    if (!isText(p.title)) { errors.push(at + ': "title" is missing'); }
    if (!isText(p.cause)) { errors.push(at + ': "cause" is missing'); }
    if (!isList(p.symptoms) || p.symptoms.length === 0 || !p.symptoms.every(isText)) {
      errors.push(at + ': "symptoms" must be a non-empty list of text');
    }

    var conditions = p.match && p.match.all;
    if (!isList(conditions) || conditions.length === 0) {
      errors.push(at + ': "match.all" must be a non-empty list');
    } else {
      conditions.forEach(function (c) {
        var def = c && signals[c.signal];
        if (!c || !isText(c.signal) || !def) { errors.push(at + ': unknown signal "' + (c && c.signal) + '"'); return; }
        if (OPS.indexOf(c.op) < 0) { errors.push(at + ': unknown operator "' + c.op + '"'); return; }
        if (c.op === 'gte' || c.op === 'lte') {
          if (typeof c.value !== 'number') { errors.push(at + ': ' + c.op + ' on ' + c.signal + ' needs a number'); }
          if (def.values !== 'number') { errors.push(at + ': ' + c.signal + ' is not a number, ' + c.op + ' does not apply'); }
        } else if (isList(def.values) && def.values.indexOf(String(c.value)) < 0) {
          errors.push(at + ': "' + c.value + '" is not a value of ' + c.signal);
        }
      });
    }

    if (!isList(p.fixes) || p.fixes.length === 0) {
      errors.push(at + ': "fixes" must be a non-empty list');
    } else {
      p.fixes.forEach(function (f) {
        var fat = at + ', fix ' + (f && f.id);
        if (!f || !isText(f.id) || !isText(f.action)) { errors.push(fat + ': "id" and "action" are required'); return; }
        if (CLASSES.indexOf(f.class) < 0) { errors.push(fat + ': unknown class "' + f.class + '"'); }
        if (EVIDENCE.indexOf(f.evidence) < 0) { errors.push(fat + ': unknown evidence "' + f.evidence + '"'); }
        ['command', 'side_effects', 'verify'].forEach(function (k) {
          if (f[k] !== undefined && !isText(f[k])) { errors.push(fat + ': "' + k + '" must be text'); }
        });
      });
    }

    if (p.not_fixes !== undefined) {
      if (!isList(p.not_fixes) || !p.not_fixes.every(function (n) { return n && isText(n.action) && isText(n.observed); })) {
        errors.push(at + ': each "not_fixes" entry needs "action" and "observed"');
      }
    }
    if (p.confirm !== undefined && (!isList(p.confirm) || !p.confirm.every(isText))) {
      errors.push(at + ': "confirm" must be a list of commands');
    }
    if (!p.evidence || EVIDENCE.indexOf(p.evidence.status) < 0) {
      errors.push(at + ': unknown evidence status "' + (p.evidence && p.evidence.status) + '"');
    }
  });
  return errors;
}

function checkShipped(kb, where) {
  var errors = [];
  if (!kb || kb.schema_version !== 1) { errors.push(where + ': "schema_version" must be 1'); }
  if (!kb.signals || typeof kb.signals !== 'object') { return errors.concat([where + ': "signals" is missing']); }
  Object.keys(kb.signals).forEach(function (name) {
    var def = kb.signals[name];
    var v = def && def.values;
    if (!def || !isText(def.description)) { errors.push(where + ': signal ' + name + ' needs a description'); }
    if (!(v === 'number' || v === 'text' || (isList(v) && v.length > 0 && v.every(isText)))) {
      errors.push(where + ': signal ' + name + ': "values" must be a list, "number" or "text"');
    }
  });
  if (!isList(kb.never) || !kb.never.every(function (n) { return n && isText(n.action) && isText(n.reason); })) {
    errors.push(where + ': each "never" entry needs "action" and "reason"');
  }
  return errors.concat(checkProblems(kb.problems, kb.signals, null, where));
}

// A copy of the problem that records which file it came from.
function withOrigin(problem, origin) {
  var copy = {};
  Object.keys(problem).forEach(function (k) { copy[k] = problem[k]; });
  copy.origin = origin;
  return copy;
}

function idsOf(problems) {
  var ids = {};
  problems.forEach(function (p) { ids[p.id] = true; });
  return ids;
}

// Loads both files. A bad shipped file is fatal. A bad personal file is reported and
// left out, so it can never hide the shipped entries.
function load(kbPath, localPath, strict) {
  var kb = readJson(kbPath);
  var errors = checkShipped(kb, 'problems.json');
  if (errors.length > 0) { errors.forEach(err); $.exit(1); }

  var localErrors = [];
  var local = [];
  if (localPath && exists(localPath)) {
    try {
      var extra = readJson(localPath);
      if (!extra || extra.schema_version !== 1) { localErrors.push('problems.local.json: "schema_version" must be 1'); }
      localErrors = localErrors.concat(checkProblems(extra.problems, kb.signals, idsOf(kb.problems), 'problems.local.json'));
      if (localErrors.length === 0) { local = extra.problems; }
    } catch (e) {
      localErrors.push(e.message);
    }
  }
  if (localErrors.length > 0) {
    localErrors.forEach(err);
    if (strict) { $.exit(1); }
    err('problems.local.json is left out until it is fixed');
  }
  var shipped = kb.problems.map(function (p) { return withOrigin(p, 'shipped'); });
  var own = local.map(function (p) { return withOrigin(p, 'local'); });
  return { kb: kb, problems: shipped.concat(own) };
}

function readSignals(path) {
  var values = {};
  readText(path).split('\n').forEach(function (line) {
    var i = line.indexOf('=');
    if (i > 0) { values[line.slice(0, i)] = line.slice(i + 1); }
  });
  return values;
}

// "Not known" must never count as a match. A signal the probe did not report makes
// its condition false whatever the operator, and so does the value "unknown", except
// for a condition that asks for "unknown" by name.
function holds(condition, values) {
  if (!Object.prototype.hasOwnProperty.call(values, condition.signal)) { return false; }
  var actual = values[condition.signal];
  if (condition.op === 'equals') { return actual === String(condition.value); }
  if (actual === 'unknown') { return false; }
  if (condition.op === 'not_equals') { return actual !== String(condition.value); }
  var n = Number(actual);
  if (actual === '' || isNaN(n)) { return false; }
  return condition.op === 'gte' ? n >= condition.value : n <= condition.value;
}

function line(p) { return [p.id, p.evidence.status, p.origin, p.title].join('\t'); }

function show(p, never) {
  var t = [];
  var local = p.origin === 'local';
  t.push(p.id + '  [' + p.evidence.status + ']');
  t.push(p.title);
  if (local) {
    t.push('來源：個人條目（problems.local.json），沒有經過審查。');
    t.push('      裡面的每一道指令，包含確認用的，都先給使用者看、同意才執行，不論 class 寫什麼。');
  } else {
    t.push('來源：隨 plugin 發布');
  }
  t.push('');
  t.push('症狀');
  p.symptoms.forEach(function (s) { t.push('  - ' + s); });
  t.push('');
  t.push('原因');
  t.push('  ' + p.cause);
  if (p.confirm) {
    t.push('');
    t.push(local ? '確認用的指令（來自個人條目，執行前先問）' : '確認用的指令（不改動設定）');
    p.confirm.forEach(function (c) { t.push('  $ ' + c); });
  }
  t.push('');
  t.push('解法（class：direct 直接做、ask 先問使用者、user 只能由使用者自己做）');
  p.fixes.forEach(function (f, i) {
    t.push('  ' + (i + 1) + '. ' + f.id + '  [class: ' + f.class + '] [evidence: ' + f.evidence + ']');
    t.push('     ' + f.action);
    if (f.command) { t.push('     $ ' + f.command); }
    if (f.side_effects) { t.push('     副作用：' + f.side_effects); }
    if (f.verify) { t.push('     驗證：' + f.verify); }
  });
  if (p.not_fixes) {
    t.push('');
    t.push('試過無效的做法');
    p.not_fixes.forEach(function (n) { t.push('  - ' + n.action + '：' + n.observed); });
  }
  t.push('');
  t.push('驗證到哪裡');
  var e = p.evidence;
  var facts = [e.status];
  if (e.date) { facts.push(e.date); }
  if (e.macos) { facts.push('macOS ' + e.macos); }
  t.push('  ' + facts.join('、'));
  if (e.note) { t.push('  ' + e.note); }
  t.push('');
  t.push('任何情況都不做');
  never.forEach(function (n) { t.push('  - ' + n.action); });
  return t.join('\n');
}

function run(argv) {
  var command = argv[0];
  var kbPath = argv[1];
  var localPath = argv[2];
  try {
    if (command === 'validate') {
      load(kbPath, localPath, true);
      out('knowledge base is valid');
      return;
    }
    var loaded = load(kbPath, localPath, false);
    if (command === 'list') {
      loaded.problems.forEach(function (p) { out(line(p)); });
      return;
    }
    if (command === 'match') {
      var values = readSignals(argv[3]);
      loaded.problems.forEach(function (p) {
        if (p.match.all.every(function (c) { return holds(c, values); })) { out(line(p)); }
      });
      return;
    }
    if (command === 'show') {
      var found = loaded.problems.filter(function (p) { return p.id === argv[3]; });
      if (found.length === 0) { err('no problem with id ' + argv[3]); $.exit(1); }
      out(show(found[0], loaded.kb.never));
      return;
    }
    err('unknown command ' + command);
    $.exit(64);
  } catch (e) {
    err(e.message);
    $.exit(1);
  }
}
