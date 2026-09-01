package main

import (
	"bytes"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"strings"
)

// --- Environment & State ---

type Environment struct {
	vars   map[string]any
	parent *Environment
}

func NewEnv(parent *Environment) *Environment {
	return &Environment{
		vars:   make(map[string]any),
		parent: parent,
	}
}

func (e *Environment) Set(name string, val any) {
	e.vars[name] = val
}

func (e *Environment) Get(name string) (any, bool) {
	if val, ok := e.vars[name]; ok {
		return val, true
	}
	if e.parent != nil {
		return e.parent.Get(name)
	}
	return nil, false
}

type Interpreter struct {
	globalEnv  *Environment
	lastPicked string
}

func NewInterpreter() *Interpreter {
	return &Interpreter{
		globalEnv:  NewEnv(nil),
		lastPicked: "",
	}
}

// --- Main Execution Engine ---

func (it *Interpreter) Run(source string) {
	lines := strings.Split(source, "\n")
	it.evalBlock(lines, it.globalEnv)
}

func (it *Interpreter) evalBlock(lines []string, env *Environment) any {
	i := 0
	for i < len(lines) {
		raw := lines[i]
		line := strings.TrimSpace(strings.ReplaceAll(raw, "\u00a0", " "))

		if line == "" || strings.HasPrefix(line, "//") {
			i++
			continue
		}

		if strings.HasPrefix(line, "if ") || line == "if" {
			condExpr := extractExpression(line, "if")
			newIdx, _ := it.handleConditionals(lines, i, condExpr, env)
			i = newIdx
			continue
		}

		if strings.HasPrefix(line, "class ") {
			i = skipBlock(lines, i)
			i++
			continue
		}

		if strings.HasPrefix(line, "fnc ") {
			i = skipBlock(lines, i)
			i++
			continue
		}

		it.evalLine(line, env)
		i++
	}
	return nil
}

func (it *Interpreter) evalLine(line string, env *Environment) any {
	if strings.Contains(line, "=") && !strings.Contains(line, "==") && !strings.HasPrefix(line, "if") {
		parts := strings.SplitN(line, "=", 2)
		varName := strings.TrimSpace(parts[0])
		rhsExpr := strings.TrimSpace(parts[1])
		varVal := it.evalExpr(rhsExpr, env)
		env.Set(varName, varVal)
		return varVal
	}

	return it.evalExpr(line, env)
}

// --- Control Flow Handlers ---

func (it *Interpreter) handleConditionals(lines []string, idx int, line string, env *Environment) (int, any) {
	condExpr := strings.TrimSpace(strings.TrimSuffix(strings.TrimPrefix(line, "if"), "{"))
	condVal := it.evalExpr(condExpr, env)
	executed := it.isTruthy(condVal)

	subLines, nextIdx := collectBlock(lines, idx)
	if executed {
		it.evalBlock(subLines, NewEnv(env))
	}

	i := nextIdx
	for i < len(lines) {
		nextLine := strings.TrimSpace(strings.ReplaceAll(lines[i], "\u00a0", " "))

		if strings.HasPrefix(nextLine, "elseif") {
			elseIfLines, nextElseIfIdx := collectBlock(lines, i)
			if !executed {
				elseIfExpr := strings.TrimSpace(strings.TrimSuffix(strings.TrimPrefix(nextLine, "elseif"), "{"))
				elseIfVal := it.evalExpr(elseIfExpr, env)
				if it.isTruthy(elseIfVal) {
					it.evalBlock(elseIfLines, NewEnv(env))
					executed = true
				}
			}
			i = nextElseIfIdx
		} else if strings.HasPrefix(nextLine, "else") || nextLine == "else" || strings.HasPrefix(nextLine, "else{") {
			elseLines, nextElseIdx := collectBlock(lines, i)
			if !executed {
				it.evalBlock(elseLines, NewEnv(env))
				executed = true
			}
			i = nextElseIdx
			break
		} else if nextLine == "" {
			i++
			continue
		} else {
			break
		}
	}

	return i, nil
}

// --- Expression & Command Evaluation ---

func (it *Interpreter) evalExpr(expr string, env *Environment) any {
	expr = strings.TrimSpace(expr)
	if strings.HasPrefix(expr, "\"") && strings.HasSuffix(expr, "\"") {
		return expr[1 : len(expr)-1]
	}
	if strings.HasPrefix(expr, "'") && strings.HasSuffix(expr, "'") {
		return expr[1 : len(expr)-1]
	}

	if strings.HasPrefix(expr, "fs.open(") && strings.HasSuffix(expr, ")") {
		content := expr[8 : len(expr)-1]
		parts := parseArgs(content)
		if len(parts) > 0 {
			filename := fmt.Sprintf("%v", it.evalExpr(parts[0], env))
			var args []string
			if len(parts) >= 2 {
				param := strings.TrimSpace(fmt.Sprintf("%v", it.evalExpr(parts[1], env)))
				if param != "" {
					args = append(args, param)
				}
			}

			cmd := exec.Command(filename, args...)
			err := cmd.Start()
			if err != nil {
				fmt.Println("Error executing file:", err)
			}
		}
		return nil
	}

	if strings.HasPrefix(expr, "net.get(") && strings.HasSuffix(expr, ")") {
		urlArg := expr[8 : len(expr)-1]
		url := strings.Trim(fmt.Sprintf("%v", it.evalExpr(urlArg, env)), "\"'")
		resp, err := http.Get(url)
		if err != nil {
			return ""
		}
		defer resp.Body.Close()
		return resp.Status
	}

	if strings.HasPrefix(expr, "net.download(") && strings.HasSuffix(expr, ")") {
		args := parseArgs(expr[13 : len(expr)-1])
		if len(args) >= 2 {
			url := strings.Trim(fmt.Sprintf("%v", it.evalExpr(args[0], env)), "\"'")
			path := strings.Trim(fmt.Sprintf("%v", it.evalExpr(args[1], env)), "\"'")
			
			resp, err := http.Get(url)
			if err != nil {
				return ""
			}
			defer resp.Body.Close()

			if resp.StatusCode != http.StatusOK {
				return ""
			}

			bodyBytes, err := io.ReadAll(resp.Body)
			if err != nil {
				return ""
			}

			_ = os.WriteFile(path, bodyBytes, 0644)
			return ""
		}
		return ""
	}

	if strings.HasPrefix(expr, "net.post(") && strings.HasSuffix(expr, ")") {
		args := parseArgs(expr[9 : len(expr)-1])
		if len(args) >= 1 {
			url := strings.Trim(fmt.Sprintf("%v", it.evalExpr(args[0], env)), "\"'")
			bodyStr := ""
			if len(args) > 1 {
				bodyStr = fmt.Sprintf("%v", it.evalExpr(args[1], env))
			}
			resp, err := http.Post(url, "text/plain", bytes.NewBuffer([]byte(bodyStr)))
			if err != nil {
				return ""
			}
			defer resp.Body.Close()
			return resp.Status
		}
		return nil
	}

	if strings.HasPrefix(expr, "net.put(") && strings.HasSuffix(expr, ")") {
		args := parseArgs(expr[8 : len(expr)-1])
		if len(args) >= 1 {
			url := strings.Trim(fmt.Sprintf("%v", it.evalExpr(args[0], env)), "\"'")
			bodyStr := ""
			if len(args) > 1 {
				bodyStr = fmt.Sprintf("%v", it.evalExpr(args[1], env))
			}
			req, _ := http.NewRequest(http.MethodPut, url, bytes.NewBuffer([]byte(bodyStr)))
			client := &http.Client{}
			resp, err := client.Do(req)
			if err != nil {
				return ""
			}
			defer resp.Body.Close()
			return resp.Status
		}
		return nil
	}

	if strings.HasPrefix(expr, "net.patch(") && strings.HasSuffix(expr, ")") {
		args := parseArgs(expr[10 : len(expr)-1])
		if len(args) >= 1 {
			url := strings.Trim(fmt.Sprintf("%v", it.evalExpr(args[0], env)), "\"'")
			bodyStr := ""
			if len(args) > 1 {
				bodyStr = fmt.Sprintf("%v", it.evalExpr(args[1], env))
			}
			req, _ := http.NewRequest(http.MethodPatch, url, bytes.NewBuffer([]byte(bodyStr)))
			client := &http.Client{}
			resp, err := client.Do(req)
			if err != nil {
				return ""
			}
			defer resp.Body.Close()
			return resp.Status
		}
		return nil
	}

	if strings.HasPrefix(expr, "net.delete(") && strings.HasSuffix(expr, ")") {
		urlArg := expr[11 : len(expr)-1]
		url := strings.Trim(fmt.Sprintf("%v", it.evalExpr(urlArg, env)), "\"'")
		req, _ := http.NewRequest(http.MethodDelete, url, nil)
		client := &http.Client{}
		resp, err := client.Do(req)
		if err != nil {
			return ""
		}
		defer resp.Body.Close()
		return resp.Status
	}

	if strings.HasPrefix(expr, "gui.alert(") && strings.HasSuffix(expr, ")") {
		msgArg := expr[10 : len(expr)-1]
		msg := strings.Trim(fmt.Sprintf("%v", it.evalExpr(msgArg, env)), "\"'")
		showWindowsMessageBox("NanoSharp Alert", msg, "Warning")
		return nil
	}

	if strings.HasPrefix(expr, "gui.error(") && strings.HasSuffix(expr, ")") {
		msgArg := expr[10 : len(expr)-1]
		msg := strings.Trim(fmt.Sprintf("%v", it.evalExpr(msgArg, env)), "\"'")
		showWindowsMessageBox("NanoSharp Error", msg, "Error")
		return nil
	}

	if strings.HasPrefix(expr, "gui.info(") && strings.HasSuffix(expr, ")") {
		msgArg := expr[9 : len(expr)-1]
		msg := strings.Trim(fmt.Sprintf("%v", it.evalExpr(msgArg, env)), "\"'")
		showWindowsMessageBox("NanoSharp Info", msg, "Information")
		return nil
	}

	if strings.HasPrefix(expr, "gui.notify(") && strings.HasSuffix(expr, ")") {
		args := parseArgs(expr[11 : len(expr)-1])
		title := "NanoSharp"
		body := ""
		if len(args) == 1 {
			body = strings.Trim(fmt.Sprintf("%v", it.evalExpr(args[0], env)), "\"'")
		} else if len(args) >= 2 {
			title = strings.Trim(fmt.Sprintf("%v", it.evalExpr(args[0], env)), "\"'")
			body = strings.Trim(fmt.Sprintf("%v", it.evalExpr(args[1], env)), "\"'")
		}
		showWindowsNotification(title, body)
		return nil
	}

	if expr == "gui.input()" || (strings.HasPrefix(expr, "gui.input(") && strings.HasSuffix(expr, ")")) {
		var title = "NanoSharp Input"
		var promptText = "Enter value:"

		if expr != "gui.input()" {
			content := expr[10 : len(expr)-1]
			if strings.TrimSpace(content) != "" {
				args := parseArgs(content)
				if len(args) == 1 {
					promptText = strings.Trim(fmt.Sprintf("%v", it.evalExpr(args[0], env)), "\"'")
				} else if len(args) >= 2 {
					title = strings.Trim(fmt.Sprintf("%v", it.evalExpr(args[0], env)), "\"'")
					promptText = strings.Trim(fmt.Sprintf("%v", it.evalExpr(args[1], env)), "\"'")
				}
			}
		}
		return showWindowsInputBox(title, promptText)
	}

	if expr == "gui.filepicker()" {
		it.lastPicked = showWindowsFilePicker()
		return it.lastPicked
	}

	if expr == "gui.filepicked()" {
		return it.lastPicked
	}

	for _, op := range []string{">=", "<=", "==", "!=", ">", "<"} {
		if strings.Contains(expr, op) {
			parts := strings.SplitN(expr, op, 2)
			left := it.evalExpr(parts[0], env)
			right := it.evalExpr(parts[1], env)
			return compareValues(left, op, right)
		}
	}

	if val, ok := env.Get(expr); ok {
		return val
	}

	if strings.HasPrefix(expr, "\"") && strings.HasSuffix(expr, "\"") {
		return expr[1 : len(expr)-1]
	}

	if n, err := strconv.Atoi(expr); err == nil {
		return n
	}

	if f, err := strconv.ParseFloat(expr, 64); err == nil {
		return f
	}

	if expr == "true" {
		return true
	}
	if expr == "false" {
		return false
	}

	return expr
}

// --- GUI Helpers with Silent Execution ---

func runSilentPowerShell(script string) string {
	cmd := exec.Command("powershell", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-Command", script)
	out, err := cmd.Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

func showWindowsMessageBox(title, message, iconType string) {
	iconEnum := "Information"
	if iconType == "Error" {
		iconEnum = "Error"
	} else if iconType == "Warning" {
		iconEnum = "Warning"
	}
	script := fmt.Sprintf(
		"Add-Type -AssemblyName PresentationCore,PresentationFramework; [System.Windows.MessageBox]::Show('%s', '%s', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::%s)",
		strings.ReplaceAll(message, "'", "''"),
		strings.ReplaceAll(title, "'", "''"),
		iconEnum,
	)
	_ = runSilentPowerShell(script)
}

func showWindowsNotification(title, message string) {
	script := fmt.Sprintf(
		"Add-Type -AssemblyName System.Windows.Forms; $notify = New-Object System.Windows.Forms.NotifyIcon; $notify.Icon = [System.Drawing.SystemIcons]::Information; $notify.Visible = $true; $notify.ShowBalloonTip(5000, '%s', '%s', [System.Windows.Forms.ToolTipIcon]::Info); Start-Sleep -Seconds 2; $notify.Dispose()",
		strings.ReplaceAll(title, "'", "''"),
		strings.ReplaceAll(message, "'", "''"),
	)
	_ = runSilentPowerShell(script)
}

func showWindowsInputBox(title, prompt string) string {
	script := fmt.Sprintf(
		"Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing; $f = New-Object System.Windows.Forms.Form; $f.Text = '%s'; $f.Size = New-Object System.Drawing.Size(400, 180); $f.StartPosition = 'CenterScreen'; $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false; $f.TopMost = $true; $l = New-Object System.Windows.Forms.Label; $l.Location = New-Object System.Drawing.Point(15, 15); $l.Size = New-Object System.Drawing.Size(350, 40); $l.Text = '%s'; $f.Controls.Add($l); $tb = New-Object System.Windows.Forms.TextBox; $tb.Location = New-Object System.Drawing.Point(15, 60); $tb.Size = New-Object System.Drawing.Size(350, 20); $f.Controls.Add($tb); $b = New-Object System.Windows.Forms.Button; $b.Location = New-Object System.Drawing.Point(210, 100); $b.Size = New-Object System.Drawing.Size(75, 25); $b.Text = 'OK'; $b.DialogResult = [System.Windows.Forms.DialogResult]::OK; $f.AcceptButton = $b; $f.Controls.Add($b); $cb = New-Object System.Windows.Forms.Button; $cb.Location = New-Object System.Drawing.Point(290, 100); $cb.Size = New-Object System.Drawing.Size(75, 25); $cb.Text = 'Cancel'; $cb.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $f.CancelButton = $cb; $f.Controls.Add($cb); [void]$f.ShowDialog(); [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; if ($f.DialogResult -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output $tb.Text }",
		strings.ReplaceAll(title, "'", "''"),
		strings.ReplaceAll(prompt, "'", "''"),
	)
	return runSilentPowerShell(script)
}

func showWindowsFilePicker() string {
	script := "Add-Type -AssemblyName System.Windows.Forms; $d = New-Object System.Windows.Forms.OpenFileDialog; $d.Title = 'Select a file'; $d.InitialDirectory = [Environment]::GetFolderPath('Desktop'); if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; Write-Output $d.FileName }"
	return runSilentPowerShell(script)
}

// --- Utility Functions ---

func compareValues(left any, op string, right any) bool {
	lInt, lIsInt := toInt(left)
	rInt, rIsInt := toInt(right)

	if lIsInt && rIsInt {
		switch op {
		case ">":
			return lInt > rInt
		case "<":
			return lInt < rInt
		case ">=":
			return lInt >= rInt
		case "<=":
			return lInt <= rInt
		case "==":
			return lInt == rInt
		case "!=":
			return lInt != rInt
		}
	}

	lStr := fmt.Sprintf("%v", left)
	rStr := fmt.Sprintf("%v", right)
	switch op {
	case "==":
		return lStr == rStr
	case "!=":
		return lStr != rStr
	}
	return false
}

func toInt(val any) (int, bool) {
	switch v := val.(type) {
	case int:
		return v, true
	case float64:
		return int(v), true
	case string:
		if n, err := strconv.Atoi(v); err == nil {
			return n, true
		}
	}
	return 0, false
}

func (it *Interpreter) isTruthy(val any) bool {
	switch v := val.(type) {
	case bool:
		return v
	case int:
		return v != 0
	case string:
		return v != "" && v != "false" && v != "0"
	default:
		return val != nil
	}
}

func extractExpression(line, keyword string) string {
	line = strings.TrimPrefix(line, keyword)
	line = strings.TrimSpace(line)
	line = strings.TrimSuffix(line, "{")
	return strings.TrimSpace(line)
}

func collectBlock(lines []string, startIdx int) ([]string, int) {
	var block []string
	depth := 0
	i := startIdx

	for i < len(lines) {
		line := strings.TrimSpace(strings.ReplaceAll(lines[i], "\u00a0", " "))
		if strings.Contains(line, "{") {
			depth++
			i++
			break
		}
		i++
	}

	for i < len(lines) {
		line := lines[i]
		trimmed := strings.TrimSpace(strings.ReplaceAll(line, "\u00a0", " "))

		if strings.Contains(trimmed, "{") {
			depth++
		}
		if strings.Contains(trimmed, "}") {
			depth--
			if depth == 0 {
				i++
				break
			}
		}

		block = append(block, line)
		i++
	}

	return block, i
}

func skipBlock(lines []string, startIndex int) int {
	_, nextIdx := collectBlock(lines, startIndex)
	return nextIdx - 1
}

func parseArgs(s string) []string {
	var args []string
	var current strings.Builder
	inQuotes := false

	for _, r := range s {
		if r == '"' {
			inQuotes = !inQuotes
			current.WriteRune(r)
		} else if r == ',' && !inQuotes {
			args = append(args, strings.TrimSpace(current.String()))
			current.Reset()
		} else {
			current.WriteRune(r)
		}
	}
	if current.Len() > 0 {
		args = append(args, strings.TrimSpace(current.String()))
	}
	return args
}

func main() {
	if len(os.Args) < 2 {
		return
	}

	filename := os.Args[1]
	if !strings.HasSuffix(filename, ".ns") {
		os.Exit(1)
	}

	content, err := os.ReadFile(filename)
	if err != nil {
		os.Exit(1)
	}

	interpreter := NewInterpreter()
	interpreter.Run(string(content))
}