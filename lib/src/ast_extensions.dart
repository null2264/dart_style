// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';

extension AstNodeExtensions on AstNode {
  /// The comma token immediately following this if there is one, or `null`.
  Token? get commaAfter {
    var next = endToken.next!;
    return switch(next) {
      case Token(type: TokenType.COMMA) => next;

      // TODO(sdk#38990): endToken doesn't include the "?" on a nullable
      // function-typed formal, so check for that case and handle it.
      case Token(type: TokenType.QUESTION, next:
              Token(type: TokenType.COMMA)!) =>
          next.next;

      default => null;
    }
  }

  /// Whether there is a comma token immediately following this.
  bool get hasCommaAfter => commaAfter != null;

  bool get isControlFlowElement => this is IfElement || this is ForElement;

  /// Whether this is immediately contained within an anonymous
  /// [FunctionExpression].
  bool get isFunctionExpressionBody =>
      parent is FunctionExpression && parent!.parent is! FunctionDeclaration;

  /// Whether [node] is a spread of a non-empty collection literal.
  bool get isSpreadCollection => spreadCollectionBracket != null;

  /// If this is a spread of a non-empty collection literal, then returns the
  /// token for the opening bracket of the collection, as in:
  ///
  ///     [ ...[a, list] ]
  ///     //   ^
  ///
  /// Otherwise, returns `null`.
  Token? get spreadCollectionBracket {
    return switch (this) {
      case SpreadElement(ListLiteral expression)
              when !expression.elements.isEmptyBody(expression.rightBracket) =>
          expression.leftBracket;
      case SpreadElement(SetOrMapLiteral expression)
              if (!expression.elements.isEmptyBody(expression.rightBracket)) =>
          expression.leftBracket;
      default => null;
    }
    // Or maybe:
    /*
    return switch (this) {
      case SpreadElement(
              expression: ListLiteral(elements, leftBracket, rightBracket))
         | SpreadElement(
              expression: SetOrMapLiteral(elements, leftBracket, rightBracket))
          when !elements.isEmptyBody(rightBracket) => leftBracket;
      default => null;
    }
    */
  }
}

extension AstIterableExtensions on Iterable<AstNode> {
  /// Whether there is a comma token immediately following this.
  bool get hasCommaAfter => isNotEmpty && last.hasCommaAfter;

  /// Whether the collection literal or block containing these nodes and
  /// terminated by [rightBracket] is empty or not.
  ///
  /// An empty collection must have no elements or comments inside. Collections
  /// like that are treated specially because they cannot be split inside.
  bool isEmptyBody(Token rightBracket) =>
      isEmpty && rightBracket.precedingComments == null;
}

extension ExpressionExtensions on Expression {
  /// Whether [expression] is a collection literal, or a call with a trailing
  /// comma in an argument list.
  ///
  /// In that case, when the expression is a target of a cascade, we don't
  /// force a split before the ".." as eagerly to avoid ugly results like:
  ///
  ///     [
  ///       1,
  ///       2,
  ///     ]..addAll(numbers);
  bool get isCollectionLike {
    switch (this) {
      case ListLiteral _ | SetOrMapLiteral _ => false;

      // If the target is a call with a trailing comma in the argument list,
      // treat it like a collection literal.
      case InvocationExpression(var argumentList)
         | InstanceCreationExpression(var argumentList) =>

        // TODO(rnystrom): Do we want to allow an invocation where the last
        // argument is a collection literal? Like:
        //
        //     foo(argument, [
        //       element
        //     ])..cascade();
        !arguments.arguments.hasCommaAfter;

      default => false;
    }
  }

  /// Whether this is an argument in an argument list with a trailing comma.
  bool get isTrailingCommaArgument {
    return switch (this) {
      case NamedExpression named => named.isTrailingCommaArgument;
      case ArgumentList(var arguments) => arguments.hasCommaAfter;
      default => false;
    }
  }

  /// Whether this is a method invocation that looks like it might be a static
  /// method or constructor call without a `new` keyword.
  ///
  /// With optional `new`, we can no longer reliably identify constructor calls
  /// statically, but we still don't want to mix named constructor calls into
  /// a call chain like:
  ///
  ///     Iterable
  ///         .generate(...)
  ///         .toList();
  ///
  /// And instead prefer:
  ///
  ///     Iterable.generate(...)
  ///         .toList();
  ///
  /// So we try to identify these calls syntactically. The heuristic we use is
  /// that a target that's a capitalized name (possibly prefixed by "_") is
  /// assumed to be a class.
  ///
  /// This has the effect of also keeping static method calls with the class,
  /// but that tends to look pretty good too, and is certainly better than
  /// splitting up named constructors.
  bool get looksLikeStaticCall {
    switch (this) {
      // A prefixed unnamed constructor call:
      //
      //     prefix.Foo();
      case MethodInvocation(SimpleIdentifier target, var methodName)
          when _looksLikeClassName(methodName.name) => true;

      // A prefixed or unprefixed named constructor call:
      //
      //     Foo.named();
      //     prefix.Foo.named();
      case MethodInvocation(PrefixedIdentifier target) =>
          target.looksLikeStaticCall;

      case SimpleIdentifier(var name) when _looksLikeClassName(name) => true;

      default => false;
    }
  }

  /// Whether [name] appears to be a type name.
  ///
  /// Type names begin with a capital letter and contain at least one lowercase
  /// letter (so that we can distinguish them from SCREAMING_CAPS constants).
  static bool _looksLikeClassName(String name) {
    // Handle the weird lowercase corelib names.
    switch (name) {
      case 'bool' | 'double' | 'int' | 'num': return true;
      default:
    }

    // TODO(rnystrom): A simpler implementation is to test against the regex
    // "_?[A-Z].*?[a-z]". However, that currently has much worse performance on
    // AOT: https://github.com/dart-lang/sdk/issues/37785.
    const underscore = 95;
    const capitalA = 65;
    const capitalZ = 90;
    const lowerA = 97;
    const lowerZ = 122;

    var start = 0;
    var firstChar = name.codeUnitAt(start++);

    // It can be private.
    if (firstChar == underscore) {
      if (name.length == 1) return false;
      firstChar = name.codeUnitAt(start++);
    }

    // It must start with a capital letter.
    if (firstChar < capitalA || firstChar > capitalZ) return false;

    // And have at least one lowercase letter in it. Otherwise it could be a
    // SCREAMING_CAPS constant.
    for (var i = start; i < name.length; i++) {
      var char = name.codeUnitAt(i);
      if (char >= lowerA && char <= lowerZ) return true;
    }

    return false;
  }
}

extension CascadeExpressionExtensions on CascadeExpression {
  /// Whether a cascade should be allowed to be inline as opposed to moving the
  /// section to the next line.
  bool get allowInline {
    // Cascades with multiple sections are handled elsewhere and are never
    // inline.
    assert(cascadeSections.length == 1);

    // If the receiver is an expression that makes the cascade's very low
    // precedence confusing, force it to split. For example:
    //
    //     a ? b : c..d();
    //
    // Here, the cascade is applied to the result of the conditional, not "c".
    return switch (this) {
      case ConditionalExpression _
         | BinaryExpression _
         | PrefixExpression _
         | AwaitExpression _ => false;
      default => true;
    }
  }
}
