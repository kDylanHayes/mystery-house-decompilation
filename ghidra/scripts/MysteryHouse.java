// Builds a Ghidra program for one Mystery House binary from the plan written by
// tools/trace6502.py, applies ghidra/symbols/<name>.csv, and writes pseudocode for every function.
//
// The binaries call a small macro library whose operands sit inline after the JSR (see
// trace6502.py). Ghidra cannot discover that by itself, so the plan lists every code byte,
// every inline operand, and the address after each operand list; this script disassembles
// exactly those bytes, marks the operands as data and overrides each such JSR's fall-through.
// In the exported C each library call is rewritten with its inline operands, e.g.
//   rt_copy(8, &input_word, &verb_word)   rt_print("ENTER COMMAND")
//
// Args: <plan.json> <symbols.csv> <out.c>
//@category MysteryHouse

import com.google.gson.*;
import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.app.cmd.function.CreateFunctionCmd;
import ghidra.app.decompiler.*;
import ghidra.app.decompiler.component.DecompilerUtils;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.*;
import ghidra.program.model.data.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.mem.*;
import ghidra.program.model.pcode.*;
import ghidra.program.model.symbol.*;
import java.nio.file.*;
import java.util.*;

public class MysteryHouse extends GhidraScript {
	AddressSpace space;
	Map<Long, String> names = new HashMap<>();
	Map<Long, JsonObject> inlineCalls = new HashMap<>();
	Map<Long, String> libOps = new HashMap<>();   // library entry -> operation name
	long lib = -1;

	Address A(long a) { return space.getAddress(a); }

	String nameOf(long a) {
		String n = names.get(a);
		if (n != null) return n;
		Symbol s = currentProgram.getSymbolTable().getPrimarySymbol(A(a));
		if (s != null && s.getSource() != SourceType.DEFAULT) return s.getName();
		return String.format("DAT_%04x", a);
	}

	String text(long a, int len) throws Exception {
		StringBuilder sb = new StringBuilder();
		for (int i = 0; i < len - 1; i++) {
			int c = currentProgram.getMemory().getByte(A(a + i)) & 0x7f;
			if (c == 0) sb.append('#');   // digit patched in at run time
			else if (c == '\r') sb.append("\\r");
			else if (c == '"') sb.append("\\\"");
			else if (c < 0x20) sb.append(String.format("\\x%02x", c));
			else sb.append((char) c);
		}
		return sb.toString();
	}

	int word(long a) throws Exception {
		Memory m = currentProgram.getMemory();
		return (m.getByte(A(a)) & 0xff) | (m.getByte(A(a + 1)) & 0xff) << 8;
	}

	/** Cover [start, start+len) with uninitialized memory, filling only the gaps between blocks
	 *  that already exist (the 6502 language predefines zero page and the stack). */
	void block(String name, long start, long len, boolean volatil) throws Exception {
		Memory m = currentProgram.getMemory();
		long a = start, end = start + len;
		int part = 0;
		while (a < end) {
			MemoryBlock have = m.getBlock(A(a));
			if (have != null) {
				a = have.getEnd().getOffset() + 1;
				continue;
			}
			long b = a;
			while (b < end && m.getBlock(A(b)) == null) b++;
			MemoryBlock nb = m.createUninitializedBlock(name + (part++ == 0 ? "" : "_" + part), A(a), b - a, false);
			nb.setWrite(true);
			nb.setVolatile(volatil);
			a = b;
		}
	}

	void label(long a, String name) throws Exception {
		if (name.isEmpty()) return;
		SymbolTable st = currentProgram.getSymbolTable();
		Symbol s = st.getPrimarySymbol(A(a));
		if (s != null && s.getSource() == SourceType.USER_DEFINED && s.getName().equals(name)) return;
		Symbol n = st.createLabel(A(a), name, SourceType.USER_DEFINED);
		n.setPrimary();
	}

	DataType type(String t) {
		int n = 1;
		int b = t.indexOf('[');
		if (b >= 0) {
			n = Integer.parseInt(t.substring(b + 1, t.length() - 1));
			t = t.substring(0, b);
		}
		DataType base;
		switch (t) {
			case "byte": base = ByteDataType.dataType; break;
			case "word": base = WordDataType.dataType; break;
			case "ptr": base = new PointerDataType(ByteDataType.dataType, 2); break;
			default: return null;
		}
		return n == 1 ? base : new ArrayDataType(base, n, base.getLength());
	}

	@Override
	public void run() throws Exception {
		String[] args = getScriptArgs();
		JsonObject plan = JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonObject();
		Path symPath = Path.of(args[1]);
		Path out = Path.of(args[2]);
		space = currentProgram.getAddressFactory().getDefaultAddressSpace();
		Listing lst = currentProgram.getListing();
		long load = plan.get("load").getAsLong();
		long end = load + plan.get("length").getAsLong();

		// Apple II memory around the image, so references resolve to named addresses
		if (load > 0) block("ram_low", 0, load, false);
		block("ram_high", end, 0xC000 - end, false);
		block("io", 0xC000, 0x100, true);
		block("rom", 0xD000, 0x3000, false);

		// symbols: address,name,type,comment
		List<String[]> syms = new ArrayList<>();
		if (Files.exists(symPath)) {
			for (String line : Files.readAllLines(symPath)) {
				if (line.isBlank() || line.startsWith("#") || line.startsWith("address,")) continue;
				String[] f = line.split(",", 4);
				syms.add(f);
				names.put(Long.parseLong(f[0].trim(), 16), f[1].trim());
			}
		}

		if (plan.has("lib") && !plan.get("lib").isJsonNull()) {
			lib = plan.get("lib").getAsLong();
			String[] ops = {"rt_copy", "rt_add8", "rt_add16", "rt_compare", "rt_args", "rt_return",
				"rt_inc16", "rt_print", "rt_mul8"};
			for (int i = 0; i < ops.length; i++) libOps.put(lib + 3 * i, ops[i]);
		}

		// inline operands become data first, so disassembly can never run into them
		for (JsonElement e : plan.getAsJsonArray("inline")) {
			JsonObject c = e.getAsJsonObject();
			inlineCalls.put(c.get("call").getAsLong(), c);
			for (JsonElement ae : c.getAsJsonArray("args")) {
				JsonObject a = ae.getAsJsonObject();
				long at = a.get("addr").getAsLong();
				int len = a.get("len").getAsInt();
				String kind = a.get("kind").getAsString();
				DataType dt = kind.equals("w") ? WordDataType.dataType
					: kind.equals("b") ? ByteDataType.dataType
					: new ArrayDataType(ByteDataType.dataType, len, 1);
				lst.createData(A(at), dt);
				if (kind.equals("s")) setEOLComment(A(at), "\"" + text(at, len) + "\"");
			}
		}

		for (MemoryBlock b : currentProgram.getMemory().getBlocks()) b.setWrite(true);

		// disassemble exactly the traced instructions, except ranges that are variables at run
		// time (ADVENTURE's start-up code at $0800 is overwritten by the HPLOT/DRAW variables)
		AddressSet dataOnly = new AddressSet();
		if (plan.has("data_only"))
			for (JsonElement e : plan.getAsJsonArray("data_only")) {
				JsonArray r = e.getAsJsonArray();
				dataOnly.add(A(r.get(0).getAsLong()), A(r.get(1).getAsLong()));
			}
		AddressSet codeSet = new AddressSet();
		for (JsonElement e : plan.getAsJsonArray("code")) {
			JsonArray p = e.getAsJsonArray();
			long a = p.get(0).getAsLong();
			codeSet.add(A(a), A(a + p.get(1).getAsInt() - 1));
		}
		codeSet = codeSet.subtract(dataOnly);
		for (JsonElement e : plan.getAsJsonArray("code")) {
			long a = e.getAsJsonArray().get(0).getAsLong();
			if (!codeSet.contains(A(a))) continue;
			if (lst.getInstructionAt(A(a)) == null) {
				DisassembleCommand cmd = new DisassembleCommand(A(a), codeSet, true);
				cmd.applyTo(currentProgram, monitor);
			}
		}
		for (JsonObject c : inlineCalls.values()) {
			Instruction ins = lst.getInstructionAt(A(c.get("call").getAsLong()));
			if (ins != null) ins.setFallThrough(A(c.get("fallthrough").getAsLong()));
		}
		Set<Long> noreturn = new HashSet<>();
		for (JsonElement e : plan.getAsJsonArray("noreturn")) noreturn.add(e.getAsLong());
		for (Instruction ins : lst.getInstructions(true)) {
			if (!ins.getMnemonicString().equals("JSR")) continue;
			Address[] f = ins.getFlows();
			if (f.length == 1 && noreturn.contains(f[0].getOffset()))
				ins.setFlowOverride(FlowOverride.CALL_RETURN);
		}
		if (plan.has("always_branches"))
			for (JsonElement e : plan.getAsJsonArray("always_branches"))
				lst.getInstructionAt(A(e.getAsLong())).setFlowOverride(FlowOverride.BRANCH);

		// jump tables: words, with references to their targets
		for (JsonElement e : plan.getAsJsonArray("jump_tables")) {
			JsonObject t = e.getAsJsonObject();
			long at = t.get("addr").getAsLong();
			int n = t.get("count").getAsInt();
			for (int i = 0; i < n; i++) {
				Address wa = A(at + 2 * i);
				if (lst.getDataAt(wa) == null) lst.createData(wa, new PointerDataType(VoidDataType.dataType, 2));
			}
		}

		// functions: traced entries plus any listed as func in the symbols
		TreeSet<Long> entries = new TreeSet<>();
		for (JsonElement e : plan.getAsJsonArray("functions")) entries.add(e.getAsLong());
		for (String[] f : syms)
			if (f.length > 2 && f[2].trim().startsWith("func")) entries.add(Long.parseLong(f[0].trim(), 16));
		entries.removeIf(a -> lst.getInstructionAt(A(a)) == null);
		// The handlers share tails (AC9000, the condition exits, ...) by jumping or branching to
		// them. Make every jump or branch to another function's entry a tail call so each tail is
		// decompiled once, as its own function, instead of being copied into every caller.
		int tails = 0;
		for (Instruction ins : lst.getInstructions(true)) {
			FlowType ft = ins.getFlowType();
			if (!ft.isJump() || ft.isComputed()) continue;
			for (Address to : ins.getFlows()) {
				if (!entries.contains(to.getOffset()) || to.equals(ins.getAddress())) continue;
				ins.setFlowOverride(FlowOverride.CALL_RETURN);
				tails++;
			}
		}
		println("MysteryHouse.java> " + tails + " jumps to shared tails made tail calls");
		// create innermost (highest) first so shared tails become their own functions
		for (Long a : entries.descendingSet()) {
			if (lst.getInstructionAt(A(a)) == null) continue;
			new CreateFunctionCmd(A(a)).applyTo(currentProgram, monitor);
		}
		FunctionManager fm = currentProgram.getFunctionManager();
		// ROM and DOS routines: no bytes here, but a one-address stub lets calls show their names
		for (String[] f : syms) {
			long a = Long.parseLong(f[0].trim(), 16);
			if (f.length < 3 || !f[2].trim().startsWith("func") || lst.getInstructionAt(A(a)) != null) continue;
			if (fm.getFunctionAt(A(a)) == null)
				fm.createFunction(f[1].trim(), A(a), new AddressSet(A(a)), SourceType.USER_DEFINED);
		}
		for (Long a : noreturn) {
			Function f = fm.getFunctionAt(A(a));
			if (f != null) f.setNoReturn(true);
		}

		// names, types and comments
		for (String[] f : syms) {
			long a = Long.parseLong(f[0].trim(), 16);
			String name = f[1].trim();
			String t = f.length > 2 ? f[2].trim() : "";
			Function fn = fm.getFunctionAt(A(a));
			if (fn != null) {
				fn.setName(name, SourceType.USER_DEFINED);
				// "func:X" / "func:A,X": parameters passed in registers
				if (t.startsWith("func:")) {
					fn.setCustomVariableStorage(true);
					for (String reg : t.substring(5).split("[;/ ]")) {
						if (reg.isEmpty()) continue;
						fn.addParameter(new ParameterImpl(reg.toLowerCase(), ByteDataType.dataType,
							currentProgram.getRegister(reg), currentProgram), SourceType.USER_DEFINED);
					}
				}
			} else label(a, name);
			DataType dt = type(t);
			if (dt != null && lst.getInstructionContaining(A(a)) == null) {
				try {
					lst.clearCodeUnits(A(a), A(a + dt.getLength() - 1), false);
					lst.createData(A(a), dt);
				} catch (Exception ex) {
					println("cannot type " + f[0] + ": " + ex.getMessage());
				}
			}
			if (f.length > 3 && !f[3].isBlank()) {
				if (fn != null) fn.setComment(f[3].trim());
				else setPlateComment(A(a), f[3].trim());
			}
		}

		export(out, plan.get("name").getAsString());
	}

	/** Rewrite a decompiled library call using the operands that follow the JSR. */
	String callText(long call, String target) throws Exception {
		JsonObject c = inlineCalls.get(call);
		if (c == null) return null;
		JsonArray a = c.getAsJsonArray("args");
		List<String> parts = new ArrayList<>();
		for (JsonElement ae : a) {
			JsonObject o = ae.getAsJsonObject();
			long at = o.get("addr").getAsLong();
			switch (o.get("kind").getAsString()) {
				case "w": parts.add("&" + nameOf(word(at))); break;
				case "b": parts.add(String.format("0x%02x", currentProgram.getMemory().getByte(A(at)) & 0xff)); break;
				default: parts.add("\"" + text(at, o.get("len").getAsInt()) + "\"");
			}
		}
		return String.join(", ", parts);
	}

	void export(Path out, String name) throws Exception {
		DecompInterface di = new DecompInterface();
		DecompileOptions opt = new DecompileOptions();
		di.setOptions(opt);
		di.toggleCCode(true);
		di.toggleSyntaxTree(true);
		di.openProgram(currentProgram);
		StringBuilder sb = new StringBuilder();
		sb.append("// ").append(name).append(": Ghidra pseudocode, regenerated by build.sh.\n");
		sb.append("// rt_* calls are the inline-operand macro library; their operands are shown as arguments.\n\n");
		int n = 0, failed = 0;
		for (Function f : currentProgram.getFunctionManager().getFunctions(true)) {
			if (currentProgram.getListing().getInstructionAt(f.getEntryPoint()) == null) continue;
			DecompileResults r = di.decompileFunction(f, 60, monitor);
			sb.append("// ").append(f.getEntryPoint()).append('\n');
			if (r == null || r.getDecompiledFunction() == null) {
				sb.append("// decompilation failed: ").append(r == null ? "" : r.getErrorMessage()).append("\n\n");
				failed++;
				continue;
			}
			ClangTokenGroup markup = r.getCCodeMarkup();
			List<ClangLine> lines = DecompilerUtils.toLines(markup);
			for (ClangLine line : lines) {
				String s = line.toString();
				// find a call on this line to a routine with inline operands
				for (int i = 0; i < line.getNumTokens(); i++) {
					ClangToken t = line.getToken(i);
					if (!(t instanceof ClangFuncNameToken)) continue;
					PcodeOp op = t.getPcodeOp();
					if (op == null || op.getOpcode() != PcodeOp.CALL) continue;
					long at = op.getSeqnum().getTarget().getOffset();
					String fn = t.getText();
					String extra = callText(at, fn);
					if (extra == null) continue;
					int p = s.indexOf(fn + "(");
					if (p < 0) continue;
					int q = s.indexOf(')', p);
					String inner = s.substring(p + fn.length() + 1, q).trim();
					s = s.substring(0, p) + fn + "(" + (inner.isEmpty() ? "" : inner + ", ") + extra + s.substring(q);
				}
				// strip the "N: " line-number prefix toString adds
				int colon = s.indexOf(": ");
				if (colon >= 0 && s.substring(0, colon).trim().matches("\\d+")) s = s.substring(colon + 2);
				s = s.strip();
				// JSR pushes its return address; Ghidra's 6502 model shows that as a store to a
				// stack variable before every call. It carries no information, so drop it.
				if (s.matches("(undefined\\d? )?uStack\\w+( = [^;]+)?;")) continue;
				sb.append("  ".repeat(line.getIndent() / 2)).append(s).append('\n');
			}
			sb.append('\n');
			n++;
		}
		Files.writeString(out, sb.toString());
		println("MysteryHouse.java> " + name + ": " + n + " functions decompiled, " + failed + " failed");
	}
}
