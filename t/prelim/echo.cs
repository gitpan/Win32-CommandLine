using System;

namespace APP { class APP {

public static void Main(string[] args)
{
	string output = "";
	for (int i = 0; i < args.Length; i++) { output += "[" + i + "]" + args[i] + "\n"; }
	Console.WriteLine( output );
}

}}