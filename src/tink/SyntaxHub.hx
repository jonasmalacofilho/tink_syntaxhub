package tink;

import haxe.macro.*;
import haxe.macro.Expr;

import tink.macro.ClassBuilder;

import tink.priority.Queue;
import tink.syntaxhub.FrontendContext;

using tink.CoreApi;
using haxe.macro.Tools;

typedef ExprLevelSyntax = {
	function appliesTo(c:ClassBuilder):Bool;
	function apply(e:Expr):Expr;
}

class SyntaxHub {
	
	static var MAIN:Null<String> = null;
	
	static function use() {
		var args = Sys.args();
		
		MAIN =
			switch args.indexOf('-main') {
				case -1: null;
				case v: args[v + 1];
			}
			
		Context.onTypeNotFound(FrontendContext.findType);
		Compiler.addGlobalMetadata('', '@:build(tink.SyntaxHub.build())', true, true, false);
	}
	
	static function build():Array<Field>
		return 
			switch Context.getLocalType() {
				case null: null;
				case TInst(_.get() => c, _):
				
					var builder = new ClassBuilder();
					
					for (plugin in classLevel.getData())
						plugin.invoke(builder);
						
					applyMainTransform(builder);
						
					return builder.export(builder.target.meta.has(':explain'));
				default: null;
			}
	
	static public var classLevel(default, null) = new Queue<Callback<ClassBuilder>>();
	static public var exprLevel(default, null) = new Queue<ExprLevelSyntax>();	
	static public var transformMain(default, null) = new Queue<Expr->Expr>();	
	
	static public var frontends(get, never):Queue<FrontendPlugin>;
	
		static inline function get_frontends()
			return FrontendContext.plugins;
	
	//TODO: at some point exposing the latter two might be a good idea
	static function simpleSugar(rule:ClassBuilder->(Expr->Expr), ?outsideIn = false) {
		return makeSyntax(function (ctx) {
			var rule = rule(ctx);
			 
			function transform(e:Expr) {
				return
					if (e == null || e.expr == null) e;
					else 
						switch e.expr {
							case EMeta( { name: ':diet' }, _): e;
							default: 
								if (outsideIn) 
									rule(e).map(transform);
								else 
									rule(e.map(transform));
						}
			}
			return transform;
		});
	}
	
	static function makeSyntax(rule:ClassBuilder->(Expr->Expr)):Callback<ClassBuilder>
		return function (ctx:ClassBuilder) {
			var rule = rule(ctx);
			function transform(f:Function)
				if (f.expr != null)
					f.expr = rule(f.expr);
			ctx.getConstructor().onGenerate(transform);
			for (m in ctx)
				switch m.kind {
					case FFun(f): transform(f);
					case FProp(_, _, _, e), FVar(_, e): 
						if (e != null)
							e.expr = rule(e).expr;//TODO: it might be better to just create a new kind, rather than modifying the expression in place
				}
		}	
	
	static function applyMainTransform(c:ClassBuilder)
		if (c.target.pack.concat([c.target.name]).join('.') == MAIN) {
			var main = c.memberByName('main').sure();
			var f = main.getFunction().sure();
			
			if (f.expr == null)
				f.expr = macro @:pos(main.pos) { };
				
			for (rule in transformMain)
				f.expr = rule(f.expr);
		}
	
	static var INITIALIZED = {
		classLevel.whenever(simpleSugar(function (c) {
			var relevant = [for (p in exprLevel.getData()) if (p.appliesTo(c)) p];
			return function (e) {
				for (p in relevant) 
					e = p.apply(e);
				return e;
			}
		}));
		true;
	}
}