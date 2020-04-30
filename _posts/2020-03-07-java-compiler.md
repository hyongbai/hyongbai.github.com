---
layout: post
title: "Java编译器的调试以及实现逻辑"
description: "Java编译器的调试以及实现逻辑"
category: all-about-tech
tags: -[java, javac, compiler]
date: 2020-03-07 21:03:57+00:00
---

## 源码

本地的javac版本为1.8.0_45

```
➜  classes git:(master) javac -version
javac 1.8.0_45
➜  classes git:(master)
```

但是我下载的是能看到的jdk8的最新版本，即`jdk8-b132`。地址如下：

<https://hg.openjdk.java.net/jdk8/jdk8/langtools/rev/c8a87a58eb3e>

也可以在里面找到其他版本。

> 这个版本支持lambda.

### # IDE

使用创建Java工程，将`src/share/classes/com/sun/tools/javac`链接到当前src内部。并使用AndroidStudio打开。

> 本地仅有AndroidStudio，如果是IntellijIDE的话则略有不同。

#### - Edit Configurations

- 点击加号(Add New Configuration)选择Application

#### - 设置Project Structure

- Source项：添加src目录。
- Paths项：Use module compile output path, 设一个output的绝对路径。
- Dependencies项：将<Module source>移动到JDK上面。(否则默认找jdk中对应的类)

#### - 重新打开Configurations

- 找到前面添加的Application。
- 设置Main class为com.sun.tools.javac.Main

#### - 设置Java Compiler

File->Settings->Build, Execution, Deployment-> Java Compiler： javac to eclipse。

### # 创建Java文件

将其路径设置到Configurations里面的Program arguments中。如：`$ProjectFileDir$/test/Test.java`

以下为我测试用的Java代码：

```java
package test;

public class Test {

    public final static String NAME = Test.class.getSimpleName();

    public static void main(String[] args) {
        final Test t = new Test("Main");
        t.funLambda(() -> {
            System.out.println("Test.funLambda invoked! name = " + t.name);
        });
    }

    ///

    String name;

    public Test(String name) {
        this.name = name;
    }

    private void funLambda(Runnable runnable) {
        runnable.run();
    }

    public class Inner {
        public void updateName(String name) {
            Test.this.name = name;
        }
    }
}
```

[![java-javac-debug-on-as-debugger.png](https://j.mp/3cEdNqz)](https://j.mp/2KimavX)

## 源码分析

![xxx](http://user-gold-cdn.xitu.io/2018/9/17/165e7947ce93f969)

> 图片来源：[深入分析 Javac 编译原理](http://j.mp/38xdbQi)

### # main()函数


```java
// src/share/classes/com/sun/tools/javac/Main.java
public class Main {

    public static void main(String[] args) throws Exception {
      if (args.length > 0 && args[0].equals("-Xjdb")) {
      // ...
      } else {
        System.exit(compile(args));
      }
    }

    public static int compile(String[] args) {
        com.sun.tools.javac.main.Main compiler =
            new com.sun.tools.javac.main.Main("javac");
        return compiler.compile(args).exitCode;
    }
}
```

主要是反射调用`com.sun.tools.javac.main.Main`的`compile()`函数，其简化逻辑如下：

```java
// src/share/classes/com/sun/tools/javac/main/Main.java
public Result compile(String[] args) {
    Context context = new Context();
    JavacFileManager.preRegister(context); // can't create it until Log has been set up
    Result result = compile(args, context);
    // ...
    return result;
}

public Result compile(...) {
        Collection<File> files;
        try {
            files = processArgs(CommandLine.parse(args), classNames);
    // ...
        if (!files.isEmpty()) {
            // add filenames to fileObjects
            comp = JavaCompiler.instance(context);
            List<JavaFileObject> otherFiles = List.nil();
            JavacFileManager dfm = (JavacFileManager)fileManager;
            for (JavaFileObject fo : dfm.getJavaFileObjectsFromFiles(files))
                otherFiles = otherFiles.prepend(fo);
            for (JavaFileObject fo : otherFiles)
                fileObjects = fileObjects.prepend(fo);
        }
        comp.compile(fileObjects, classnames.toList(), processors);
    // ...
    return Result.OK;
}
```

这里大致分2步：

```
graph LR
processArgs-->compile
```

- 解析args。

获取参数中的**java源文件**列表。

注意：java源文件必须以`.java`结尾(废话), 具体过程见 [*processArgs()*](https://j.mp/2VWtiEm) 函数。

- 调用JavaCompiler的compile函数。

继续执行编译过程。

### # JavaCompiler


```
graph LR
initProcessAnnotations-->parseFiles
parseFiles-->processAnnotations
processAnnotations-->compile2
```


```java
// src/share/classes/com/sun/tools/javac/main/JavaCompiler.java
public void compile(List<JavaFileObject> sourceFileObjects,
                    List<String> classnames,
                    Iterable<? extends Processor> processors)
{
    // ...
        initProcessAnnotations(processors);
        delegateCompiler =
            processAnnotations(enterTrees(stopIfError(CompileState.PARSE, parseFiles(sourceFileObjects))), classnames);
        delegateCompiler.compile2();
    // ...
}
```

这里主要5个逻辑：

- initProcessAnnotations

初始化注解处理器。（默认注解处理器为空，关于注解处理器可以参考android的apt等）

- parseFiles

解析Java源文件。

- enterTrees

- processAnnotations

处理注解。

- compile2

通过代理继续编译。

下面继续分析 `parseFiles` 和 `compile2` 过程

## 解析Java源文件

简单来说就是：

Java文件解析过程依次为Token化，之后生成[JCTree](https://j.mp/3aBBU7o)。最终将所有JCTree组合成一个[JCCompilationUnit](https://j.mp/2TWLevQ)。

流程：

```
graph LR
Source-->Tokenizer
Tokenizer-->JCTree
JCTree-->JCCompilationUnit
```

parseFiles的实现如下：

```
// src/share/classes/com/sun/tools/javac/main/JavaCompiler.java
public List<JCCompilationUnit> parseFiles(Iterable<JavaFileObject> fileObjects) {
   if (shouldStop(CompileState.PARSE))
       return List.nil();

    //parse all files
    ListBuffer<JCCompilationUnit> trees = new ListBuffer<>();
    Set<JavaFileObject> filesSoFar = new HashSet<JavaFileObject>();
    // 遍历从编译参数中获得的文件列表
    for (JavaFileObject fileObject : fileObjects) {
        if (!filesSoFar.contains(fileObject)) {
            filesSoFar.add(fileObject);
            // 解析单个java文件生成JCCompilationUnit
            trees.append(parse(fileObject));
        }
    }
    return trees.toList();
}
```

逐个文件进行解析，如下：

```java
// src/share/classes/com/sun/tools/javac/main/JavaCompiler.java
public JCTree.JCCompilationUnit parse(JavaFileObject filename) {
    JavaFileObject prev = log.useSource(filename);
    try {
        JCTree.JCCompilationUnit t = parse(filename, readSource(filename));
        if (t.endPositions != null) log.setEndPosTable(filename, t.endPositions);
        return t;
    } finally {
        log.useSource(prev);
    }
}

protected JCCompilationUnit parse(JavaFileObject filename, CharSequence content) {
    JCCompilationUnit tree = make.TopLevel(List.<JCTree.JCAnnotation>nil(), null, List.<JCTree>nil());
    ...
    // 创建JavacParser，内部会创建对应的词法分析器(Lexer)
    Parser parser = parserFactory.newParser(content, keepComments(), genEndPos, lineDebugInfo);
    // 解析获取JCCompilationUnit
    tree = parser.parseCompilationUnit();
    // ...
    tree.sourcefile = filename;
    //...
    return tree;
}
```

其中filename为当前的java文件，而content就是java文件的所有内容。接着使用parserFactory为每个文件创建一个解释器。

- 解释器创建

过程包含如下逻辑:

创建词法分析器: Lexer。Scanner with JavaTokenizer。

初始化解析器: JavacParser。

- 生成JCTree即JCCompilationUnit

Javac中对于源码的解析都是以JCTree的形式组织的。

同时`JCCompilationUnit`也是一个JCTree。它本身包含了一系列的子JCTree。

> JCTree应该翻译成编译树？

### # 源文件解析

JavacParser初始化如下：

```java
// src/share/classes/com/sun/tools/javac/parser/ParserFactory.java
public JavacParser newParser(CharSequence input, boolean keepDocComments, boolean keepEndPos, boolean keepLineMap) {
    Lexer lexer = scannerFactory.newScanner(input, keepDocComments);
    return new JavacParser(this, lexer, keepDocComments, keepLineMap, keepEndPos);
}

// src/share/classes/com/sun/tools/javac/parser/JavacParser.java
protected JavacParser(ParserFactory fac, Lexer S, boolean keepDocComments, boolean keepLineMap, boolean keepEndPositions) {
    this.S = S;
    // 解析第一个token出来。这个Token其实就是这个文件的第一个关键词。比如package或者import。
    nextToken(); // prime the pump
    ...
    this.allowGenerics = source.allowGenerics();
    this.allowVarargs = source.allowVarargs();
    ...
    this.allowLambda = source.allowLambda() &&
            fac.options.isSet("allowLambda");
    this.allowMethodReferences = source.allowMethodReferences() &&
            fac.options.isSet("allowMethodReferences");
    ...
}
```

> 对lambda的编译支持不仅要求allowLambda(即java8或者以上)并且要求options.isSet("allowLambda")
>
> (即编译参数明确指出allowLambda)。

构建好JavacParser之后就进入到真正的解析过程了。

解析过程（即生成JCCompilationUnit的过程）分为如下两部分：

- 分析/解析Token: 词法分析

- 分析/组合Token为JCTree: 语法(格式)分析

### # 词法分析-Token化(Tokenizer)

读出单个字符然后根据对应解析规则，给当位置往后剥离关键词。之后根据关键词生成不同类型的Token。

> 因为解析关键词以及名字等词所以叫词法分析。。。吧。

在JavaParser构造函数时调用了`nextToken`创建第一token，函数如下：

```java
// src/share/classes/com/sun/tools/javac/parser/JavacParser.java
public void nextToken() {
    // S为JavaScanner:Lexer。从头开始持续往下读取/解析下一个token
    S.nextToken();
    // 拿到当前已解析出的token。
    token = S.token();
}
```

Scanner提供`nextToken`函数从头开始持续往下读取/解析下一个Token存储在其内部的token变量中。

#### - 解析Token过程

Scanner的`nextToken`函数，最终使用的是JavaTokenizer实现，如下：

```java
// src/share/classes/com/sun/tools/javac/parser/JavaTokenizer.java
public Token readToken() {

    // 清除reader中buffer的index
    reader.sp = 0;
    name = null;
    radix = 0;

    int pos = 0;
    int endPos = 0;
    List<Comment> comments = null;

    try {
        loop: while (true) {
            pos = reader.bp;
            switch (reader.ch) {
            // ...
            case '1': case '2': case '3': case '4':
            case '5': case '6': case '7': case '8': case '9':
                // 表示遇到了10进制数字(包含整型/浮点等)
                // 注意这里并不包括0，因为0可能出现0x/0b等非10进制的情况。 0的处理在原函数这个位置的上一个case，这里省略了。
                scanNumber(pos, 10);
                break loop;
            case '.':
                reader.scanChar(); // 读取下一个字符
                if ('0' <= reader.ch && reader.ch <= '9') {
                    // "."后面是数字，那么认定为浮点数。并向buffer中写入'.'
                    reader.putChar('.');
                    scanFractionAndSuffix(pos);
                } else if (reader.ch == '.') {
                    int savePos = reader.bp;
                    reader.putChar('.'); reader.putChar('.', true);
                    if (reader.ch == '.') {
                        // 出现3个dot（即"..."），表示省略号。比如声明为变长参数就会有这个情况。
                        reader.scanChar();
                        reader.putChar('.');
                        tk = TokenKind.ELLIPSIS;
                    } else {
                        // 非法的dot
                        lexError(savePos, "illegal.dot");
                    }
                } else {
                    // 否则就是一个点，比如访问object的函数/变量等。
                    tk = TokenKind.DOT;
                }
                break loop;
            case ',':
                reader.scanChar(); tk = TokenKind.COMMA; break loop;
            ...
            case '/':
                reader.scanChar();
                if (reader.ch == '/') {
                    // 解析单行注释
                    do {
                        reader.scanCommentChar();
                    } while (reader.ch != CR && reader.ch != LF && reader.bp < reader.buflen);
                    if (reader.bp < reader.buflen) {
                        comments = addComment(comments, processComment(pos, reader.bp, CommentStyle.LINE));
                    }
                    break;
                } else if (reader.ch == '*') {
                    // 解析多行注释
                    boolean isEmpty = false;
                    reader.scanChar();
                    CommentStyle style;
                    if (reader.ch == '*') {
                        style = CommentStyle.JAVADOC;
                        reader.scanCommentChar();
                        if (reader.ch == '/') {
                            isEmpty = true;
                        }
                    } else {
                        style = CommentStyle.BLOCK;
                    }
                    while (!isEmpty && reader.bp < reader.buflen) {
                        if (reader.ch == '*') {
                            reader.scanChar();
                            if (reader.ch == '/') break;
                        } else {
                            reader.scanCommentChar();
                        }
                    }
                    if (reader.ch == '/') {
                        reader.scanChar();
                        comments = addComment(comments, processComment(pos, reader.bp, style));
                        break;
                    } else {
                        lexError(pos, "unclosed.comment");
                        break loop;
                    }
                } else if (reader.ch == '=') {
                    // 解析‘/=’即除等于
                    tk = TokenKind.SLASHEQ;
                    reader.scanChar();
                } else {
                    // 解析斜杠‘/’，这里应该是除以的意思。
                    tk = TokenKind.SLASH;
                }
                break loop;
            ...
            }
        }
        endPos = reader.bp;
        // 更加TokenKind的TAG生成对应的Token类的实例
        switch (tk.tag) {
            case DEFAULT: return new Token(tk, pos, endPos, comments);
            case NAMED: return new NamedToken(tk, pos, endPos, name, comments);
            case STRING: return new StringToken(tk, pos, endPos, reader.chars(), comments);
            case NUMERIC: return new NumericToken(tk, pos, endPos, reader.chars(), radix, comments);
            default: throw new AssertionError();
        }
    }
    ...
}
```

`readToken`可概括为如下两部分：

- 算法定义token

上面分别列出了数字、点(.)、斜线(/)、等于(=)等情况下应该如何处理。

- 创建Token对象

根据上面定义的token位置，以及TokenKind实例化Token或者其子类。

其中`reader.chars()`表示读取buffer中的数据。当TokenKind为STRING或者NUMBER时，需要其原始值。

我使用的Java编译器版本定义了114种Token样式即(TokenKind), 最终按照TAG又可以分4组：

> TokenKid列表见：[src/share/classes/com/sun/tools/javac/parser/Tokens.java](https://j.mp/39D1J74)

这4组Token的说明如下：

- DEFAULT

源码中所有保留的关键词对应类型的TAG。比如: `public`/`class`/`[`/`{`/`.`/`;`等等。

对应的就是Token这个类。

- NAMED

变量/类名/函数/以及部分保留词(比如: void/true/null等)等等。

对应的是Token的子类`NamedToken`。

- STRING

源码中出现的字符常量。

对应的是Token的子类`StringToken`。

- NUMERIC

源码中出现的数字的值。

对应的是Token的子类`NumericToken`。

Token的构造函数如下：

```java
// src/share/classes/com/sun/tools/javac/parser/Tokens.java
Token(TokenKind kind, int pos, int endPos, List<Comment> comments) {
    this.kind = kind;
    this.pos = pos;
    this.endPos = endPos;
    this.comments = comments;
    checkKind();
}
```

下面举例说明Token是如何解析的。

#### - Tokenizer举例

比如：

```
public String[] arr = { "A" };
```

解析出对应的Token列表是

源码字符 | Token
|:-:|:-:|
`public`|   new `Token`(`PUBLIC`, 0, 6, null);
`String`|   new `NamedToken`(`IDENTIFIER`, 7, 13, null);
`[`|        new `Token`(`LBRACKET`, 13, 14, null);
`]`|        new `Token`(`RBRACKET`, 14, 15, null);
`arr`|      new `NamedToken`(`IDENTIFIER`, 15, 18, null);
`=`|        new `Token`(`EQ`, 19, 20, null);
`{`|        new `Token`(`LBRACE`, 21, 22, null);
`"A"`|      new `StringToken`(`STRINGLITERAL`, 23, 26, null);
`}`|        new `Token`(`RBRACE`, 27, 28, null);
`;`|        new `Token`(`SEMI`, 28, 29, null);

[![java-javac-javaTokenizer-readTooken-ancient-way.png](https://j.mp/330C6uf)](https://j.mp/2v8pbKu)

### # 生成JCCompilationUnit (语法格式分析)

这一步会以Token为单位进行组合和解析。

如出现语法错误则会直接抛出语法错误，中断编译。

这里所说的语法分析主要就格式而言，比如某一行函数是否以`SEMI(;)`结尾或者`LBRACE({)`同`RBRACE(})`是否关闭等等。

同时生成SyntaxError，如下：

```
// src/share/classes/com/sun/tools/javac/parser/JavacParser.java
private JCErroneous syntaxError(int pos, String key, TokenKind... args) {
    return syntaxError(pos, List.<JCTree>nil(), key, args);
}

private JCErroneous syntaxError(int pos, List<JCTree> errs, String key, TokenKind... args) {
    setErrorEndPos(pos);
    JCErroneous err = F.at(pos).Erroneous(errs);
    reportSyntaxError(err, key, (Object[])args);
    if (errs != null) {
        JCTree last = errs.last();
        if (last != null)
            storeEnd(last, pos);
    }
    return toP(err);
}
```

回到上面的`parseCompilationUnit()`函数。

简化如下：

```java
// src/share/classes/com/sun/tools/javac/parser/JavacParser.java
public JCTree.JCCompilationUnit parseCompilationUnit() {
    Token firstToken = token;
    ...
    if (token.kind == PACKAGE) {
        // 处理package声明
        seenPackage = true;
        if (mods != null) {
            checkNoMods(mods.flags);
            packageAnnotations = mods.annotations;
            mods = null;
        }
        nextToken();
        // 读取报名其实就是xxx.xxx.xxx的一组字符。
        pid = qualident(false);
        accept(SEMI);
    }
    ListBuffer<JCTree> defs = new ListBuffer<JCTree>();
    while (token.kind != EOF) {
        ...
        if (checkForImports && mods == null && token.kind == IMPORT) {
            seenImport = true;
            // 当前token是IMPORT，那么即认为这是一个import语句，因此接下来将解析出一个表示import语句的JCTree了。
            defs.append(importDeclaration());
        } else {
            ...
            // 其他情况则认为是Type，即Class、Enum或者Interface了。即类声明(JCClassDecl)。
            JCTree def = typeDeclaration(mods, docComment);
            if (def instanceof JCExpressionStatement)
                def = ((JCExpressionStatement)def).expr;
            defs.append(def);
            ...
        }
    }
    // 由此可见，每一个JCCompilationUnit可能包含了一个package、import、type等。
    JCTree.JCCompilationUnit toplevel = F.at(firstToken.pos).TopLevel(packageAnnotations, pid, defs.toList());
    ...
    return toplevel;
}
```

javac解析源码时，会将所有字符串token化。根据token类型组合成对应的[JCTree](https://j.mp/3aBBU7o)。

解析包名用到的`qualident`函数如下:

```java
// src/share/classes/com/sun/tools/javac/parser/JavacParser.java
public JCExpression qualident(boolean allowAnnos) {
    JCExpression t = toP(F.at(token.pos).Ident(ident()));
    while (token.kind == DOT) {
        int pos = token.pos;
        nextToken();
        List<JCAnnotation> tyannos = null;
        if (allowAnnos) {
            tyannos = typeAnnotationsOpt();
        }
        t = toP(F.at(pos).Select(t, ident()));
        if (tyannos != null && tyannos.nonEmpty()) {
            t = toP(F.at(tyannos.head.pos).AnnotatedType(tyannos, t));
        }
    }
    return t;
}
```

qualident就是一直读遇到DOT则认为是一个新的包往JCTree里面添加节点。

排除package，可以看到这里主要处理了两部分：

```
graph LR
JCImport-->JCClassDecl
```

#### - 声明导入importDeclaration

将每个import开头的token都解析成一个JCTree(即Import对象)。

```java
// src/share/classes/com/sun/tools/javac/parser/JavacParser.java
JCTree importDeclaration() {
    int pos = token.pos;
    nextToken();
    boolean importStatic = false;
    if (token.kind == STATIC) {
        checkStaticImports();
        importStatic = true;
        nextToken();
    }
    // pid(JCExpression)按照字面意思就是表达式，其实就是xxx.xxx.xxx
    JCExpression pid = toP(F.at(token.pos).Ident(ident()));
    do {
        int pos1 = token.pos;
        accept(DOT);
        if (token.kind == STAR) {
            // 处理通配符
            pid = to(F.at(pos1).Select(pid, names.asterisk));
            nextToken();
            break;
        } else {
            // 正常导入
            pid = toP(F.at(pos1).Select(pid, ident()));
        }
    } while (token.kind == DOT);
    // 到这里之后reader应该以";"结尾"，否则抛出语法错误的异常。在这一步(解析阶段)只关注代码格式是否正确，比如括弧/注释是否闭合等等。而不关心某个变量/类是否合法。
    accept(SEMI);
    // 创建一个Import对象。
    return toP(F.at(pos).Import(pid, importStatic));
}
```

其中`F.at(pos).Import(pid, importStatic)`就是创建一个Import对象，如下：

```java
// src/share/classes/com/sun/tools/javac/tree/TreeMaker.java
public TreeMaker at(int pos) {
    this.pos = pos;
    return this;
}
public JCImport Import(JCTree qualid, boolean importStatic) {
    JCImport tree = new JCImport(qualid, importStatic);
    tree.pos = pos;
    return tree;
}
```

而`toP(T)`函数，最终返回的还是参数本身。如下：

```java
// src/share/classes/com/sun/tools/javac/parser/JavacParser.java
private <T extends JCTree> T toP(T t) {
    return endPosTable.toP(t);
}


// src/share/classes/com/sun/tools/javac/parser/JavacParser.java$SimpleEndPosTable
protected <T extends JCTree> T toP(T t) {
    // 将当前的JCTree对象及上一个Token的endPos进行映射存储出来。
    storeEnd(t, parser.S.prevToken().endPos);
    return t;
}

public void storeEnd(JCTree tree, int endpos) {
    endPosMap.put(tree, errorEndPos > endpos ? errorEndPos : endpos);
}
```

其中 toP() 函数则是将当前的JCTree对象，即上一个Token的endPos(即在源文件中的结束位置)进行映射存储在endPosTable对象中。

这里需要解释以下，在`importDeclaration()`的尾部，有一个`accept(SEMI);`语句。这句话的意思是当前的token必须是SEMI，否则抛出语法异常。如下：

```java
// src/share/classes/com/sun/tools/javac/parser/JavacParser.java
public void accept(TokenKind tk) {
    if (token.kind == tk) {
        // 继续往后解析下一个token
        nextToken();
    } else {
        // 标记出错位置，并抛出语法异常: error: ';' expected
        setErrorEndPos(token.pos);
        reportSyntaxError(S.prevToken().endPos, "expected", tk);
    }
}
```

也就是说`endPosTable`中存的value为当前JCTree的“;”的位置，即语句结束的位置。同时继续往后解析下一个token。

抛出的错误如下：

```
/Volumes/Data/projects/jdk8-langtools/example/test/Test.java:3: error: ';' expected
import java.lang.String
                       ^
1 error
```

#### - typeDeclaration

用于生成类或者接口以及枚举对应的JCTree。

```java
// src/share/classes/com/sun/tools/javac/parser/JavacParser.java
JCTree typeDeclaration(JCModifiers mods, Comment docComment) {
    // ...
    return classOrInterfaceOrEnumDeclaration(modifiersOpt(mods), docComment);
}

JCStatement classOrInterfaceOrEnumDeclaration(JCModifiers mods, Comment dc) {
    if (token.kind == CLASS) {
        return classDeclaration(mods, dc);
    } else if (token.kind == INTERFACE) {
        return interfaceDeclaration(mods, dc);
    } else if (allowEnums) {
        if (token.kind == ENUM) {
            return enumDeclaration(mods, dc);
        }
    // ...
}
```

对应的是java支持的三种定义：类(class) / 接口(Interface) / 枚举(ENUM)。

以 `类(class)` 为例，其实现为`classDeclaration`如下：

```java
// src/share/classes/com/sun/tools/javac/parser/JavacParser.java
protected JCClassDecl classDeclaration(JCModifiers mods, Comment dc) {
    int pos = token.pos;
    accept(CLASS);
    Name name = ident();
    List<JCTypeParameter> typarams = typeParametersOpt(); // 解析泛型
    JCExpression extending = null;
    if (token.kind == EXTENDS) {
        nextToken(); // 下一个token
        extending = parseType(); // 解析Parent
    }
    List<JCExpression> implementing = List.nil();
    if (token.kind == IMPLEMENTS) {
        // 解析继承的所有接口，这个是一个列表
        nextToken();
        implementing = typeList();
    }
    // 解析body
    List<JCTree> defs = classOrInterfaceBody(name, false);
    JCClassDecl result = toP(F.at(pos).ClassDef(
        mods, name, typarams, extending, implementing, defs));
    attach(result, dc);
    return result;
}
```

这里可以简单分为类的`类型`和`body`，最终返回一个 [` JCClassDecl `](https://j.mp/2wPya3t) 对象。

**解析类型**

- typeParametersOpt：解析泛型
- parseType：解析出PARENT
- typeList：解析出接口列表

解析泛型:

```
// src/share/classes/com/sun/tools/javac/parser/JavacParser.java
List<JCTypeParameter> typeParametersOpt() {
    if (token.kind == LT) { //以左箭头开始
        checkGenerics();
        ListBuffer<JCTypeParameter> typarams = new ListBuffer<JCTypeParameter>();
        nextToken();
        typarams.append(typeParameter());
        while (token.kind == COMMA) {
            nextToken();
            typarams.append(typeParameter());
        }
        accept(GT); // 必须以右箭头结束
        return typarams.toList();
    } else {
        return List.nil();
    }
}
```

从`LT`(即`<`)开始到`GT`(即`>`)结束, 中间以`COMMA`间隔获取多个泛型。逻辑比较简单。

解析父类/接口过程略。

**解析Body**

类的body部分才是整个类的核心，所有逻辑都在body中。比如变量的定义、函数的定义等待。

Body由`classOrInterfaceBody`生成：

```java
// src/share/classes/com/sun/tools/javac/parser/JavacParser.java
/** ClassBody     = "{" {ClassBodyDeclaration} "}"
 *  InterfaceBody = "{" {InterfaceBodyDeclaration} "}"
 */
List<JCTree> classOrInterfaceBody(Name className, boolean isInterface) {
    accept(LBRACE);
    // ...
    ListBuffer<JCTree> defs = new ListBuffer<JCTree>();
    while (token.kind != RBRACE && token.kind != EOF) {
        defs.appendList(classOrInterfaceBodyDeclaration(className, isInterface));
        // ...
    }
    accept(RBRACE);
    return defs.toList();
}
```

这个函数这里只有一个逻辑：循环读取`LBRACE`和`RBRACE`中间的所有声明。

这些声明包含`变量`、`函数`、`内部类`、`枚举`、`代码块`等等。

同时这些所有的声明也都是一个一个的JCTree组成。

来看`classOrInterfaceBodyDeclaration`:

```java
// src/share/classes/com/sun/tools/javac/parser/JavacParser.java
protected List<JCTree> classOrInterfaceBodyDeclaration(Name className, boolean isInterface) {
    if (token.kind == SEMI) {
        nextToken();
        return List.<JCTree>nil();
    } else {
        Comment dc = token.comment(CommentStyle.JAVADOC);
        int pos = token.pos;
        // 解析修饰符，比如PUBLIC/STATIC/FINAL/ABSTRACT/VOLATILE等等
        JCModifiers mods = modifiersOpt();
        if (token.kind == CLASS ||
            token.kind == INTERFACE ||
            allowEnums && token.kind == ENUM) {
            // 遇到内部类、接口、枚举，则进入下一个Type循环。
            return List.<JCTree>of(classOrInterfaceOrEnumDeclaration(mods, dc));
        } else if (token.kind == LBRACE && !isInterface &&
                   (mods.flags & Flags.StandardFlags & ~Flags.STATIC) == 0 &&
                   mods.annotations.isEmpty()) {
            // 遇到左大括弧"{", 开始解析代码块(block)
            return List.<JCTree>of(block(pos, mods.flags));
        } else {
            pos = token.pos;
            List<JCTypeParameter> typarams = typeParametersOpt();
            if (typarams.nonEmpty() && mods.pos == Position.NOPOS) {
                mods.pos = pos;
                storeEnd(mods, pos);
            }
            List<JCAnnotation> annosAfterParams = annotationsOpt(Tag.ANNOTATION);

            Token tk = token;
            pos = token.pos;
            JCExpression type;
            boolean isVoid = token.kind == VOID;
            if (isVoid) {
                if (annosAfterParams.nonEmpty())
                    illegal(annosAfterParams.head.pos);
                type = to(F.at(pos).TypeIdent(TypeTag.VOID));
                nextToken();
            } else {
                if (annosAfterParams.nonEmpty()) {
                    mods.annotations = mods.annotations.appendList(annosAfterParams);
                    if (mods.pos == Position.NOPOS)
                        mods.pos = mods.annotations.head.pos;
                }
                // method returns types are un-annotated types
                type = unannotatedType();
            }
            if (token.kind == LPAREN && !isInterface && type.hasTag(IDENT)) {
                if (isInterface || tk.name() != className)
                    error(pos, "invalid.meth.decl.ret.type.req");
                return List.of(methodDeclaratorRest(
                    pos, mods, null, names.init, typarams,
                    isInterface, true, dc));
            } else {
                pos = token.pos;
                Name name = ident();
                if (token.kind == LPAREN) {
                    return List.of(methodDeclaratorRest(
                        pos, mods, type, name, typarams,
                        isInterface, isVoid, dc));
                } else if (!isVoid && typarams.isEmpty()) {
                    List<JCTree> defs =
                        variableDeclaratorsRest(pos, mods, type, name, isInterface, dc,
                                                new ListBuffer<JCTree>()).toList();
                    storeEnd(defs.last(), token.endPos);
                    accept(SEMI);
                    return defs;
                } else {
                    pos = token.pos;
                    List<JCTree> err = isVoid
                        ? List.<JCTree>of(toP(F.at(pos).MethodDef(mods, name, type, typarams,
                            List.<JCVariableDecl>nil(), List.<JCExpression>nil(), null, null)))
                        : null;
                    return List.<JCTree>of(syntaxError(token.pos, err, "expected", LPAREN));
                }
            }
        }
    }
}
```

这里可以看到分别对上面提到的几种声明的实现：

- classOrInterfaceOrEnumDeclaration：构建当前类的内部类/内部接口/内部枚举
- variableDeclaratorsRest：构建变量
- methodDeclaratorRest：构建函数
- block：构建代码块

这四种类型的确立的简单逻辑是：
- 通过判断TokenKind是否为`CLASS`/`INTERFACE`/`ENUM`确定`classOrInterfaceOrEnum`
- 通过判断是否是`LBRACE`(即`{`)等来确定block
- 判断`LPAREN`(即`(`)来确定函数
- 最后大概就是变量了。
- 如果都不是那就抛出语法错误。

下面以函数为例来看构建函数的JCTree的过程。

**构建函数器(methodDeclarator)**

```java
// src/share/classes/com/sun/tools/javac/parser/JavacParser.java
protected JCTree methodDeclaratorRest(int pos,
                          JCModifiers mods,
                          JCExpression type,
                          Name name,
                          List<JCTypeParameter> typarams,
                          boolean isInterface, boolean isVoid,
                          Comment dc) {
    if (isInterface && (mods.flags & Flags.STATIC) != 0) {
        checkStaticInterfaceMethods();
    }
    JCVariableDecl prevReceiverParam = this.receiverParam;
    try {
        this.receiverParam = null;
        // Parsing formalParameters sets the receiverParam, if present
        List<JCVariableDecl> params = formalParameters();
        if (!isVoid) type = bracketsOpt(type);
        List<JCExpression> thrown = List.nil();
        if (token.kind == THROWS) {
            nextToken();
            thrown = qualidentList();
        }
        JCBlock body = null;
        JCExpression defaultValue;
        if (token.kind == LBRACE) {
            body = block();
            defaultValue = null;
        } else {
            // ...
        }

        JCMethodDecl result =
                toP(F.at(pos).MethodDef(mods, name, type, typarams,
                                        receiverParam, params, thrown,
                                        body, defaultValue));
        attach(result, dc);
        return result;
    } finally {
        this.receiverParam = prevReceiverParam;
    }
}

JCBlock block(int pos, long flags) {
    accept(LBRACE);
    List<JCStatement> stats = blockStatements();
    JCBlock t = F.at(pos).Block(flags, stats);
    while (token.kind == CASE || token.kind == DEFAULT) {
        syntaxError("orphaned", token.kind);
        switchBlockStatementGroups();
    }
    // the Block node has a field "endpos" for first char of last token, which is
    // usually but not necessarily the last char of the last token.
    t.endpos = token.pos;
    accept(RBRACE);
    return toP(t);
}
```

TOOD: [`blockStatement()`](https://j.mp/3aBdsTM)包括了对代码块的完整解析。比如各种关键词，以及变量声明、函数调用等等。

### # 源文件解析总结

源文件解析主要两个阶段即：词法分析(JavaTokenizer:Lexer)和语法分析(JCCompilationUnit:JCTree )。

- **词法分析**

即是将所有保留字段、字符、词组生成一个个Token。如果出现非法则使用TokenKind.ERROR标记，并且抛出AssertionError。具体逻辑在[JavaTokenizer.readToken()](https://j.mp/2W1BTpf)中。

- **语法分析**

则是在Lexer(Tokenizer)生成的Token基础上按照import/class/interface/enum/method/variable/block等方式组装成对应的JCTree。如组装过程中发现校验失败则会生成一个JCErroneous(JCTree)，在最终组装编译单元(即JCCompilationUnit)校验出并抛出AssertionError([TreeMaker.TopLevel()](https://j.mp/38GZqP4))。语法分析具体逻辑入口：[JavacParser.parseCompilationUnit()](https://j.mp/3cKTrMm)。

在这一步(解析阶段)只关注代码格式是否正确，比如括弧/注释是否闭合等等，上面提到的各种accpet就是干这个活的。而不关心某个变量/类是否合法。

下图为这个Test.java最终生成的JCTree：

[![java8-javac-JavaParser-parseCompilationUnit-Test.png](https://j.mp/2KarLnb)](https://j.mp/34LiuLR)

文件解析完之后就进行后面的编译过程了。

## enterTrees

Javac对JCTree的访问基于访问者模式，JCTree$Visitor定义了一系列接口。其中每个JCTree的子类对应着一个方法。

其实现逻辑大致为：

继承 `JCTree$Visitor`，根据自身业务(比如想遍历所有函数，那么就需要从 `JCTree$JCCompilationUnit` 一直遍历到JVMethorDecl借口)，实现需要访问的对象的接口。

JCTree内部有个 `accept(Visitor v)` 方法，在子类中重写这个方法，调用visitor对应当前子类的方法。比如 `JCTree$JCCompilationUnit` 的 `accept(Visitor v)` 方法体为 `v.visitTopLevel(this)` ，其他的比如Import对应的为 `visitImport(JCImport that)` 等等。

[>>> `JCTree$Visitor`类源码传送门 <<<](http://hg.openjdk.java.net/jdk8/jdk8/langtools/file/c8a87a58eb3e/src/share/classes/com/sun/tools/javac/tree/JCTree.java#l2526)

### # Enter

下面继续接着上面来到 `enterTrees` 这一步。

Enter主要是将JCTree转化成对应的Symbol: TypeSymbol/PackageSymbol/ClassSymbol。

并且根据className以及Package等信息，将Symbol组合/连接起来，形成“引用”关系。

比如一个Package包含的多个Child Package，或者一个Child Packager的Owner Package；一个ClassSymbol对应的Package。

```java
// src/share/classes/com/sun/tools/javac/main/JavaCompiler.java
/**
 * Enter the symbols found in a list of parse trees.
 * As a side-effect, this puts elements on the "todo" list.
 * Also stores a list of all top level classes in rootClasses.
 */
public List<JCCompilationUnit> enterTrees(List<JCCompilationUnit> roots) {
    ...
    enter.main(roots);
    ...
    // If generating source, or if tracking public apis,
    // then remember the classes declared in
    // the original compilation units listed on the command line.
    if (needRootClasses || sourceOutput || stubOutput) {
        ListBuffer<JCClassDecl> cdefs = new ListBuffer<>();
        for (JCCompilationUnit unit : roots) {
            for (List<JCTree> defs = unit.defs;
                 defs.nonEmpty();
                 defs = defs.tail) {
                if (defs.head instanceof JCClassDecl)
                    cdefs.append((JCClassDecl)defs.head);
            }
        }
        rootClasses = cdefs.toList();
    }

    // Ensure the input files have been recorded. Although this is normally
    // done by readSource, it may not have been done if the trees were read
    // in a prior round of annotation processing, and the trees have been
    // cleaned and are being reused.
    for (JCCompilationUnit unit : roots) {
        inputFiles.add(unit.sourcefile);
    }

    return roots;
}
```

```java
// src/share/classes/com/sun/tools/javac/comp/Enter.java
public void main(List<JCCompilationUnit> trees) {
    complete(trees, null);
}

public void complete(List<JCCompilationUnit> trees, ClassSymbol c) {
    annotate.enterStart();
    ListBuffer<ClassSymbol> prevUncompleted = uncompleted;
    if (memberEnter.completionEnabled) uncompleted = new ListBuffer<ClassSymbol>();

    try {
        // 开始遍历所有的编译树：JCCompilationUnit
        classEnter(trees, null);
        // complete all uncompleted classes in memberEnter
        if  (memberEnter.completionEnabled) {
            while (uncompleted.nonEmpty()) {
                ClassSymbol clazz = uncompleted.next();
                if (c == null || c == clazz || prevUncompleted == null)
                    clazz.complete();
                else
                    // defer
                    prevUncompleted.append(clazz);
            }

            // if there remain any unimported toplevels (these must have
            // no classes at all), process their import statements as well.
            for (JCCompilationUnit tree : trees) {
                if (tree.starImportScope.elems == null) {
                    JavaFileObject prev = log.useSource(tree.sourcefile);
                    Env<AttrContext> topEnv = topLevelEnv(tree);
                    memberEnter.memberEnter(tree, topEnv);
                    log.useSource(prev);
                }
            }
        }
    }
}
```

`classEnter`函数是JSTree调用Visitor访问的触发处：

```java
// src/share/classes/com/sun/tools/javac/comp/Enter.java
<T extends JCTree> List<Type> classEnter(List<T> trees, Env<AttrContext> env) {
    ListBuffer<Type> ts = new ListBuffer<Type>();
    for (List<T> l = trees; l.nonEmpty(); l = l.tail) {
        Type t = classEnter(l.head, env);
        if (t != null) ts.append(t);
    }
    return ts.toList();
}

Type classEnter(JCTree tree, Env<AttrContext> env) {
    Env<AttrContext> prevEnv = this.env;
    try {
        // 进入accept之前，将当前env变量保存起来，并切换成外面的env。运行结束之后再回退回去。
        this.env = env;
        tree.accept(this);
        return result;
    } finally {
        this.env = prevEnv;
    }
}

```

可以看到最终调用了tree.accept(Visitor)接口。由上面可以，这一次调用到classEnter的JCTree肯定是最顶端的JCCompilationUnit，下面来看看其accpet及之后是如何实现的。

### # visitTopLevel

`JCTree$JCCompilationUnit` 对应的visit方法为 `visitTopLevel` ，因此继续看Enter的visitTopLevel方法：


```java
// src/share/classes/com/sun/tools/javac/tree/JCTree$JCCompilationUnit.java
public void accept(Visitor v) { v.visitTopLevel(this); }

// src/share/classes/com/sun/tools/javac/comp/Enter.java
@Override
public void visitTopLevel(JCCompilationUnit tree) {
    JavaFileObject prev = log.useSource(tree.sourcefile);
    boolean addEnv = false;
    boolean isPkgInfo = tree.sourcefile.isNameCompatible("package-info",JavaFileObject.Kind.SOURCE);
    if (tree.pid != null) {
        // pid其实就是class的包名，这里会将包名及其parent一层层遍历出来生成对应的对象，并缓存起来。
        // 也就是说所有的JCTree中相同的包名，对应的都是同一个 `PackageSymbol` 对象。
        tree.packge = reader.enterPackage(TreeInfo.fullName(tree.pid));
        if (tree.packageAnnotations.nonEmpty()
                || pkginfoOpt == PkgInfo.ALWAYS
                || tree.docComments != null) {
            if (isPkgInfo) {
                addEnv = true;
            } else if (tree.packageAnnotations.nonEmpty()){
                log.error(tree.packageAnnotations.head.pos(), "pkg.annotations.sb.in.package-info.java");
            }
        }
    } else {
        tree.packge = syms.unnamedPackage;
    }
    tree.packge.complete(); // Find all classes in package.
    Env<AttrContext> topEnv = topLevelEnv(tree);
    ...
    // 继续遍历JCCompilationUnit包含的子JCTree：Import/Class/Interface/Enum等等。
    classEnter(tree.defs, topEnv);
    if (addEnv) {
        todo.append(topEnv);
    }
    log.useSource(prev);
    result = null;
}

Env<AttrContext> topLevelEnv(JCCompilationUnit tree) {
    Env<AttrContext> localEnv = new Env<AttrContext>(tree, new AttrContext());
    localEnv.toplevel = tree;
    localEnv.enclClass = predefClassDef;
    tree.namedImportScope = new ImportScope(tree.packge);
    tree.starImportScope = new StarImportScope(tree.packge);
    localEnv.info.scope = tree.namedImportScope;
    localEnv.info.lint = lint;
    return localEnv;
}
```

### # visitClassDef

```java
// src/share/classes/com/sun/tools/javac/comp/Enter.java
@Override
public void visitClassDef(JCClassDecl tree) {
    Symbol owner = env.info.scope.owner;
    Scope enclScope = enterScope(env);
    ClassSymbol c;
    if (owner.kind == PCK) {
        // We are seeing a toplevel class.
        PackageSymbol packge = (PackageSymbol)owner;
        for (Symbol q = packge; q != null && q.kind == PCK; q = q.owner) q.flags_field |= EXISTS;
        c = reader.enterClass(tree.name, packge);
        packge.members().enterIfAbsent(c);
        ...
    } else {
        if (!tree.name.isEmpty() &&
            !chk.checkUniqueClassName(tree.pos(), tree.name, enclScope)) {
            result = null;
            return;
        }
        if (owner.kind == TYP) {
            // We are seeing a member class.
            c = reader.enterClass(tree.name, (TypeSymbol)owner);
            if ((owner.flags_field & INTERFACE) != 0) {
                // 如果当前的JCTree对应的onwer是一个INTERFACE，即接口类的内部类。
                // 那么这个内部类无论如何将会被定义为PUBLIC STATIC。
                tree.mods.flags |= PUBLIC | STATIC;
            }
        } else {
            // 即不是Package内直接定义的类，也不是Type(Class/Interface/Enum)内部的类。
            // 那么这个类就是一个localClass。
            c = reader.defineClass(tree.name, owner);
            c.flatname = chk.localClassName(c);
            if (!c.name.isEmpty()) chk.checkTransparentClass(tree.pos(), c, env.info.scope);
        }
    }
    // 为JCTree内部的sym成员设定对应的symbol实例。
    tree.sym = c;

    // 如果这个类先前加入过`compiled`，那么直接从这里退出。
    if (chk.compiled.get(c.flatname) != null) {
        duplicateClass(tree.pos(), c);
        result = types.createErrorType(tree.name, (TypeSymbol)owner, Type.noType);
        tree.sym = (ClassSymbol)result.tsym;
        return;
    }
    chk.compiled.put(c.flatname, c);
    enclScope.enter(c);

    // Set up an environment for class block and store in `typeEnvs'
    // table, to be retrieved later in memberEnter and attribution.
    Env<AttrContext> localEnv = classEnv(tree, env);
    typeEnvs.put(c, localEnv);

    // 设定symbol的completer回调为memberEnter。
    // MemberEnter是一个专门用于处理Class内部成员变量/方法的Visitor。
    c.completer = memberEnter;
    c.flags_field = chk.checkFlags(tree.pos(), tree.mods.flags, c, tree);
    c.sourcefile = env.toplevel.sourcefile;
    c.members_field = new Scope(c);

    ClassType ct = (ClassType)c.type;
    if (owner.kind != PCK && (c.flags_field & STATIC) == 0) {
        // We are seeing a local or inner class.
        // Set outer_field of this class to closest enclosing class
        // which contains this class in a non-static context
        // (its "enclosing instance class"), provided such a class exists.
        Symbol owner1 = owner;
        while ((owner1.kind & (VAR | MTH)) != 0 &&
               (owner1.flags_field & STATIC) == 0) {
            owner1 = owner1.owner;
        }
        if (owner1.kind == TYP) {
            ct.setEnclosingType(owner1.type);
        }
    }

    // Enter type parameters.
    ct.typarams_field = classEnter(tree.typarams, localEnv);

    // 非local，则加入到uncompleted列表中。
    if (!c.isLocal() && uncompleted != null) uncompleted.append(c);

    // 继续访问Class内部的子树。
    classEnter(tree.defs, localEnv);

    result = c.type;
}
```

- 创建Symbol实例

根据onwer的不同使用不同的策略创建Symbol对象。

同时，如果这是一个接口类的内部类，那么这个内部类会被标记为`public static`。

这里关于localClass，有一个简单的定义：如果一个类即不是Package内直接定义的类，也不是Type(Class/Interface/Enum)内部的类，那么这个类就是一个localClass。

- 加入缓存

每一个被处理的JCTree都会加入到`compiled`列表中。如果已加入，则代表处理过。因此无需走后面的逻辑，直接跳出即可。

- 初始化成员相关操作

这里主要是设定completer，即一个结束时的回调。在后面处理uncompeleted的时候，会用到这个completer。

因为Enter最多处理到JCClassDecl，因此只算是处理了一半。那么剩下的一半是什么呢？

很明显，类的成员(包括成员变量以及成员函数并未处理)。所以这个completer就是一个用于专门处理其成员的Visitor，即`MemberEnter`：

```
c.completer = memberEnter
```

- 加入uncompleted列表

`uncompleted` 列表保存了那些需要处理成员的非localClass。

以 `Test.java` 而言，uncompleted的值如下：

```
uncompleted = {ListBuffer@1076}  size = 2
 0 = {Symbol$ClassSymbol@1180} "Test"
 1 = {Symbol$ClassSymbol@1181} "Test.Task"
```

- 遍历子树

最后可以看到`visitClassDef`会一直遍历其内部的子树，直到子树没有子树。

`Enter`只处理了JCCompilationUnit和JCClassDecl。其他的，比如函数等都没有处理。

默认的visitTree函数空实现如下：

```java
// src/share/classes/com/sun/tools/javac/comp/Enter.java
@Override
public void visitTree(JCTree tree) {
    result = null;
}
```

Javac中，对于JCTree到Symbol的处理，可以分为Enter、MemberEnter、Attr等。

### # MemberEnter

```java
// src/share/classes/com/sun/tools/javac/comp/MemberEnter.java
public void complete(Symbol sym) throws CompletionFailure {
    ...
    ClassSymbol c = (ClassSymbol)sym;
    ClassType ct = (ClassType)c.type;
    Env<AttrContext> env = enter.typeEnvs.get(c);
    JCClassDecl tree = (JCClassDecl)env.tree;
    boolean wasFirst = isFirst;
    isFirst = false;

    JavaFileObject prev = log.useSource(env.toplevel.sourcefile);
    DiagnosticPosition prevLintPos = deferredLintHandler.setPos(tree.pos());
    try {
        // 加入到待完成队列，继续处理Class内部的JCVariableDecl以及JCMethodDecl
        halfcompleted.append(env);

        // Mark class as not yet attributed.
        c.flags_field |= UNATTRIBUTED;

        // If this is a toplevel-class, make sure any preceding import
        // clauses have been seen.
        if (c.owner.kind == PCK) {
            // 访问Toplevel即JCCompilationUnit，对应的访问函数为内部的MemberEnter#visitTopLevel()函数
            memberEnter(env.toplevel, env.enclosing(TOPLEVEL));
            // 将Class对应的Env添加到todo中，供编译器完成compile2阶段：语义分析以及字节码生成。
            todo.append(env);
        }

        if (c.owner.kind == TYP) c.owner.complete();

        // create an environment for evaluating the base clauses
        Env<AttrContext> baseEnv = baseEnv(tree, env);

        if (tree.extending != null) typeAnnotate(tree.extending, baseEnv, sym, tree.pos());
        for (JCExpression impl : tree.implementing) typeAnnotate(impl, baseEnv, sym, tree.pos());
        annotate.flush();

        // Determine supertype.
        Type supertype =
            (tree.extending != null)
            ? attr.attribBase(tree.extending, baseEnv, true, false, true)
            : ((tree.mods.flags & Flags.ENUM) != 0)
            ? attr.attribBase(enumBase(tree.pos, c), baseEnv,
                              true, false, false)
            : (c.fullname == names.java_lang_Object)
            ? Type.noType
            : syms.objectType;
        ct.supertype_field = modelMissingTypes(supertype, tree.extending, false);

        // Determine interfaces.
        ListBuffer<Type> interfaces = new ListBuffer<Type>();
        ListBuffer<Type> all_interfaces = null; // lazy init
        Set<Type> interfaceSet = new HashSet<Type>();
        List<JCExpression> interfaceTrees = tree.implementing;
        for (JCExpression iface : interfaceTrees) {
            Type i = attr.attribBase(iface, baseEnv, false, true, true);
            if (i.hasTag(CLASS)) {
                interfaces.append(i);
                if (all_interfaces != null) all_interfaces.append(i);
                chk.checkNotRepeated(iface.pos(), types.erasure(i), interfaceSet);
            } else {
                if (all_interfaces == null)
                    all_interfaces = new ListBuffer<Type>().appendList(interfaces);
                all_interfaces.append(modelMissingTypes(i, iface, true));
            }
        }
        if ((c.flags_field & ANNOTATION) != 0) {
            ct.interfaces_field = List.of(syms.annotationType);
            ct.all_interfaces_field = ct.interfaces_field;
        }  else {
            ct.interfaces_field = interfaces.toList();
            ct.all_interfaces_field = (all_interfaces == null)
                    ? ct.interfaces_field : all_interfaces.toList();
        }

        if (c.fullname == names.java_lang_Object) {
            if (tree.extending != null) {
                chk.checkNonCyclic(tree.extending.pos(), supertype);
                ct.supertype_field = Type.noType;
            }
            else if (tree.implementing.nonEmpty()) {
                chk.checkNonCyclic(tree.implementing.head.pos(), ct.interfaces_field.head);
                ct.interfaces_field = List.nil();
            }
        }

        // Annotations.
        ...

        // Add default constructor if needed.
        if ((c.flags() & INTERFACE) == 0 &&
            !TreeInfo.hasConstructors(tree.defs)) {
            List<Type> argtypes = List.nil();
            List<Type> typarams = List.nil();
            List<Type> thrown = List.nil();
            long ctorFlags = 0;
            boolean based = false;
            boolean addConstructor = true;
            ...
            if (addConstructor) {
                MethodSymbol basedConstructor = nc != null ?
                        (MethodSymbol)nc.constructor : null;
                JCTree constrDef = DefaultConstructor(make.at(tree.pos), c,
                                                    basedConstructor,
                                                    typarams, argtypes, thrown,
                                                    ctorFlags, based);
                tree.defs = tree.defs.prepend(constrDef);
            }
        }

        // enter symbols for 'this' into current scope.
        VarSymbol thisSym =
            new VarSymbol(FINAL | HASINIT, names._this, c.type, c);
        thisSym.pos = Position.FIRSTPOS;
        env.info.scope.enter(thisSym);
        // if this is a class, enter symbol for 'super' into current scope.
        if ((c.flags_field & INTERFACE) == 0 && ct.supertype_field.hasTag(CLASS)) {
            VarSymbol superSym =
                new VarSymbol(FINAL | HASINIT, names._super, ct.supertype_field, c);
            superSym.pos = Position.FIRSTPOS;
            env.info.scope.enter(superSym);
        }
        ...
    }
    ...
    // Enter all member fields and methods of a set of half completed classes in a second phase.
    if (wasFirst) {
        try {
            while (halfcompleted.nonEmpty()) {
                Env<AttrContext> toFinish = halfcompleted.next();
                finish(toFinish);
                ...
            }
        } finally {
            isFirst = true;
        }
    }
}
```

#### - MemberEnter.visitTopLevel

```java
    public void visitTopLevel(JCCompilationUnit tree) {
        if (tree.starImportScope.elems != null) {
            // we must have already processed this toplevel
            return;
        }

        // check that no class exists with same fully qualified name as
        // toplevel package
        if (checkClash && tree.pid != null) {
            Symbol p = tree.packge;
            while (p.owner != syms.rootPackage) {
                p.owner.complete(); // enter all class members of p
                if (syms.classes.get(p.getQualifiedName()) != null) {
                    log.error(tree.pos,
                              "pkg.clashes.with.class.of.same.name",
                              p);
                }
                p = p.owner;
            }
        }

        // process package annotations
        annotateLater(tree.packageAnnotations, env, tree.packge, null);

        DiagnosticPosition prevLintPos = deferredLintHandler.immediate();
        Lint prevLint = chk.setLint(lint);

        try {
            // Import-on-demand java.lang.
            importAll(tree.pos, reader.enterPackage(names.java_lang), env);

            // Process all import clauses.
            memberEnter(tree.defs, env);
        } finally {
            chk.setLint(prevLint);
            deferredLintHandler.setPos(prevLintPos);
        }
    }
```

#### - visitVarDef

```java
// src/share/classes/com/sun/tools/javac/comp/MemberEnter.java
public void visitVarDef(JCVariableDecl tree) {
    Env<AttrContext> localEnv = env;
    if ((tree.mods.flags & STATIC) != 0 ||
        (env.info.scope.owner.flags() & INTERFACE) != 0) {
        localEnv = env.dup(tree, env.info.dup());
        localEnv.info.staticLevel++;
    }
    DiagnosticPosition prevLintPos = deferredLintHandler.setPos(tree.pos());
    annotate.enterStart();
    try {
        try {
            if (TreeInfo.isEnumInit(tree)) {
                attr.attribIdentAsEnumType(localEnv, (JCIdent)tree.vartype);
            } else {
                attr.attribType(tree.vartype, localEnv);
                if (tree.nameexpr != null) {
                    attr.attribExpr(tree.nameexpr, localEnv);
                    MethodSymbol m = localEnv.enclMethod.sym;
                    if (m.isConstructor()) {
                        Type outertype = m.owner.owner.type;
                        if (outertype.hasTag(TypeTag.CLASS)) {
                            checkType(tree.vartype, outertype, "incorrect.constructor.receiver.type");
                            checkType(tree.nameexpr, outertype, "incorrect.constructor.receiver.name");
                        } else {
                            log.error(tree, "receiver.parameter.not.applicable.constructor.toplevel.class");
                        }
                    } else {
                        checkType(tree.vartype, m.owner.type, "incorrect.receiver.type");
                        checkType(tree.nameexpr, m.owner.type, "incorrect.receiver.name");
                    }
                }
            }
        } finally {
            deferredLintHandler.setPos(prevLintPos);
        }

        if ((tree.mods.flags & VARARGS) != 0) {
            //if we are entering a varargs parameter, we need to
            //replace its type (a plain array type) with the more
            //precise VarargsType --- we need to do it this way
            //because varargs is represented in the tree as a
            //modifier on the parameter declaration, and not as a
            //distinct type of array node.
            ArrayType atype = (ArrayType)tree.vartype.type.unannotatedType();
            tree.vartype.type = atype.makeVarargs();
        }
        Scope enclScope = enter.enterScope(env);
        VarSymbol v =
            new VarSymbol(0, tree.name, tree.vartype.type, enclScope.owner);
        v.flags_field = chk.checkFlags(tree.pos(), tree.mods.flags, v, tree);
        tree.sym = v;
        if (tree.init != null) {
            v.flags_field |= HASINIT;
            if ((v.flags_field & FINAL) != 0 &&
                needsLazyConstValue(tree.init)) {
                Env<AttrContext> initEnv = getInitEnv(tree, env);
                initEnv.info.enclVar = v;
                v.setLazyConstValue(initEnv(tree, initEnv), attr, tree);
            }
        }
        if (chk.checkUnique(tree.pos(), v, enclScope)) {
            chk.checkTransparentVar(tree.pos(), v, enclScope);
            enclScope.enter(v);
        }
        annotateLater(tree.mods.annotations, localEnv, v, tree.pos());
        typeAnnotate(tree.vartype, env, v, tree.pos());
        v.pos = tree.pos;
    } finally {
        annotate.enterDone();
    }
}
```

#### - visitMethodDef

```java
// src/share/classes/com/sun/tools/javac/comp/MemberEnter.java
public void visitMethodDef(JCMethodDecl tree) {
    Scope enclScope = enter.enterScope(env);
    MethodSymbol m = new MethodSymbol(0, tree.name, null, enclScope.owner);
    m.flags_field = chk.checkFlags(tree.pos(), tree.mods.flags, m, tree);
    tree.sym = m;

    //if this is a default method, add the DEFAULT flag to the enclosing interface
    if ((tree.mods.flags & DEFAULT) != 0) {
        m.enclClass().flags_field |= DEFAULT;
    }

    Env<AttrContext> localEnv = methodEnv(tree, env);

    annotate.enterStart();
    try {
        DiagnosticPosition prevLintPos = deferredLintHandler.setPos(tree.pos());
        try {
            // Compute the method type
            m.type = signature(m, tree.typarams, tree.params,
                               tree.restype, tree.recvparam,
                               tree.thrown,
                               localEnv);
        } finally {
            deferredLintHandler.setPos(prevLintPos);
        }

        if (types.isSignaturePolymorphic(m)) {
            m.flags_field |= SIGNATURE_POLYMORPHIC;
        }

        // Set m.params
        ListBuffer<VarSymbol> params = new ListBuffer<VarSymbol>();
        JCVariableDecl lastParam = null;
        for (List<JCVariableDecl> l = tree.params; l.nonEmpty(); l = l.tail) {
            JCVariableDecl param = lastParam = l.head;
            params.append(Assert.checkNonNull(param.sym));
        }
        m.params = params.toList();

        // mark the method varargs, if necessary
        if (lastParam != null && (lastParam.mods.flags & Flags.VARARGS) != 0)
            m.flags_field |= Flags.VARARGS;

        localEnv.info.scope.leave();
        if (chk.checkUnique(tree.pos(), m, enclScope)) {
        enclScope.enter(m);
        }

        annotateLater(tree.mods.annotations, localEnv, m, tree.pos());
        // Visit the signature of the method. Note that
        // TypeAnnotate doesn't descend into the body.
        typeAnnotate(tree, localEnv, m, tree.pos());

        if (tree.defaultValue != null)
            annotateDefaultValueLater(tree.defaultValue, localEnv, m);
    } finally {
        annotate.enterDone();
    }
}
```

#### - signature

```java
// src/share/classes/com/sun/tools/javac/comp/MemberEnter.java
Type signature(MethodSymbol msym,
               List<JCTypeParameter> typarams,
               List<JCVariableDecl> params,
               JCTree res,
               JCVariableDecl recvparam,
               List<JCExpression> thrown,
               Env<AttrContext> env) {

    // Enter and attribute type parameters.
    List<Type> tvars = enter.classEnter(typarams, env);
    attr.attribTypeVariables(typarams, env);

    // Enter and attribute value parameters.
    ListBuffer<Type> argbuf = new ListBuffer<Type>();
    for (List<JCVariableDecl> l = params; l.nonEmpty(); l = l.tail) {
        memberEnter(l.head, env);
        argbuf.append(l.head.vartype.type);
    }

    // Attribute result type, if one is given.
    Type restype = res == null ? syms.voidType : attr.attribType(res, env);

    // Attribute receiver type, if one is given.
    Type recvtype;
    if (recvparam!=null) {
        memberEnter(recvparam, env);
        recvtype = recvparam.vartype.type;
    } else {
        recvtype = null;
    }

    // Attribute thrown exceptions.
    ListBuffer<Type> thrownbuf = new ListBuffer<Type>();
    for (List<JCExpression> l = thrown; l.nonEmpty(); l = l.tail) {
        Type exc = attr.attribType(l.head, env);
        if (!exc.hasTag(TYPEVAR)) {
            exc = chk.checkClassType(l.head.pos(), exc);
        } else if (exc.tsym.owner == msym) {
            //mark inference variables in 'throws' clause
            exc.tsym.flags_field |= THROWS;
        }
        thrownbuf.append(exc);
    }
    MethodType mtype = new MethodType(argbuf.toList(),
                                restype,
                                thrownbuf.toList(),
                                syms.methodClass);
    mtype.recvtype = recvtype;
    return tvars.isEmpty() ? mtype : new ForAll(tvars, mtype);
}
```


## 编译阶段(compile2)

在这个阶段，java文件均已经解析完成。同时java文件的注解信息也已经完成。

```java
// src/share/classes/com/sun/tools/javac/main/JavacParser.java
private void compile2() {
    try {
        switch (compilePolicy) {
        // ...
        case BY_TODO:
            while (!todo.isEmpty())
                generate(desugar(flow(attribute(todo.remove()))));
            break;
    // ...
}
```

可以分为如下四个步骤：

```
graph LR
attribute-->flow
flow-->desugar
desugar-->generate
```

### # attribute(语法逻辑分析)

比如引用某个不存在的变量、调用某个不存在的函数等等，都会在这里抛出相应异常。

```java
// src/share/classes/com/sun/tools/javac/comp/Attr.java
/** Finish the attribution of a class. */
private void attribClassBody(Env<AttrContext> env, ClassSymbol c) {
    JCClassDecl tree = (JCClassDecl)env.tree;
    Assert.check(c == tree.sym);

    // Validate type parameters, supertype and interfaces.
    attribStats(tree.typarams, env);
    if (!c.isAnonymous()) {
        //already checked if anonymous
        chk.validate(tree.typarams, env);
        chk.validate(tree.extending, env);
        chk.validate(tree.implementing, env);
    }

    // If this is a non-abstract class, check that it has no abstract
    // methods or unimplemented methods of an implemented interface.
    if ((c.flags() & (ABSTRACT | INTERFACE)) == 0) {
        if (!relax)
            chk.checkAllDefined(tree.pos(), c);
    }
    // ...
    // Check that class does not import the same parameterized with two different argument lists.
    chk.checkClassBounds(tree.pos(), c.type);

    tree.type = c.type;

    for (List<JCTypeParameter> l = tree.typarams;
         l.nonEmpty(); l = l.tail) {
         Assert.checkNonNull(env.info.scope.lookup(l.head.name).scope);
    }

    // Check that a generic class doesn't extend Throwable
    if (!c.type.allparams().isEmpty() && types.isSubtype(c.type, syms.throwableType))
        log.error(tree.extending.pos(), "generic.throwable");

    // Check that all methods which implement some method conform to the method they implement.
    chk.checkImplementations(tree);

    //check that a resource implementing AutoCloseable cannot throw InterruptedException
    checkAutoCloseable(tree.pos(), env, c.type);

    for (List<JCTree> l = tree.defs; l.nonEmpty(); l = l.tail) {
        // Attribute declaration
        attribStat(l.head, env);
        // Check that declarations in inner classes are not static (JLS 8.1.2) Make an exception for static constants.
        if (c.owner.kind != PCK &&
            ((c.flags() & STATIC) == 0 || c.name == names.empty) &&
            (TreeInfo.flags(l.head) & (STATIC | INTERFACE)) != 0) {
            Symbol sym = null;
            if (l.head.hasTag(VARDEF)) sym = ((JCVariableDecl) l.head).sym;
            if (sym == null || sym.kind != VAR ||
                ((VarSymbol) sym).getConstValue() == null)
                log.error(l.head.pos(), "icls.cant.have.static.decl", c);
        }
    }

    // Check for cycles among non-initial constructors.
    chk.checkCyclicConstructors(tree);
    // Check for cycles among annotation elements.
    chk.checkNonCyclicElements(tree);
    // ...
}
```

[![java-javac-compile2-attribute-attribClassBody-tree.png](https://j.mp/2QjhdWn)](https://j.mp/2TS4jzj)

就可见性而言，如下可以用于查找Identifier(即变量名/函数名/包名等)是否可达：

```
// src/share/classes/com/sun/tools/javac/comp/Resolve.java
/** Find an unqualified identifier which matches a specified kind set.
 */
Symbol findIdent(Env<AttrContext> env, Name name, int kind) {
    Symbol bestSoFar = typeNotFound;
    Symbol sym;

    if ((kind & VAR) != 0) {
        sym = findVar(env, name);
        if (sym.exists()) return sym;
        else if (sym.kind < bestSoFar.kind) bestSoFar = sym;
    }

    if ((kind & TYP) != 0) {
        sym = findType(env, name);
        if (sym.kind==TYP) {
             reportDependence(env.enclClass.sym, sym);
        }
        if (sym.exists()) return sym;
        else if (sym.kind < bestSoFar.kind) bestSoFar = sym;
    }

    if ((kind & PCK) != 0) return reader.enterPackage(name);
    else return bestSoFar;
}
```

这里的根据当前JCIdent的类型及其名字通过不同的函数实现。以查找变量为例:

```java
// src/share/classes/com/sun/tools/javac/comp/Resolve.java
Symbol findVar(Env<AttrContext> env, Name name) {
    Symbol bestSoFar = varNotFound;
    Symbol sym;
    Env<AttrContext> env1 = env;
    boolean staticOnly = false;
    while (env1.outer != null) {
        if (isStatic(env1)) staticOnly = true;
        Scope.Entry e = env1.info.scope.lookup(name);
        while (e.scope != null &&
               (e.sym.kind != VAR ||
                (e.sym.flags_field & SYNTHETIC) != 0))
            e = e.next();
        sym = (e.scope != null)
            ? e.sym
            : findField(
                env1, env1.enclClass.sym.type, name, env1.enclClass.sym);
        if (sym.exists()) {
            if (staticOnly &&
                sym.kind == VAR &&
                sym.owner.kind == TYP &&
                (sym.flags() & STATIC) == 0)
                return new StaticError(sym);
            else
                return sym;
        } else if (sym.kind < bestSoFar.kind) {
            bestSoFar = sym;
        }

        if ((env1.enclClass.sym.flags() & STATIC) != 0) staticOnly = true;
        env1 = env1.outer;
    }

    sym = findField(env, syms.predefClass.type, name, syms.predefClass);
    if (sym.exists())
        return sym;
    if (bestSoFar.exists())
        return bestSoFar;

    Symbol origin = null;
    for (Scope sc : new Scope[] { env.toplevel.namedImportScope, env.toplevel.starImportScope }) {
        Scope.Entry e = sc.lookup(name);
        for (; e.scope != null; e = e.next()) {
            sym = e.sym;
            if (sym.kind != VAR)
                continue;
            // invariant: sym.kind == VAR
            if (bestSoFar.kind < AMBIGUOUS && sym.owner != bestSoFar.owner)
                return new AmbiguityError(bestSoFar, sym);
            else if (bestSoFar.kind >= VAR) {
                origin = e.getOrigin().owner;
                bestSoFar = isAccessible(env, origin.type, sym)
                    ? sym : new AccessError(env, origin.type, sym);
            }
        }
        if (bestSoFar.exists()) break;
    }
    if (bestSoFar.kind == VAR && bestSoFar.owner.type != origin.type)
        return bestSoFar.clone(origin);
    else
        return bestSoFar;
}
```

### # DataFlowAnalysis(语义分析)

[Flow.java](https://j.mp/2Ix2X7U)

```java
// src/share/classes/com/sun/tools/javac/comp/Flow.java
public void analyzeTree(Env<AttrContext> env, TreeMaker make) {
    new AliveAnalyzer().analyzeTree(env, make);
    new AssignAnalyzer(log, syms, lint, names).analyzeTree(env);
    new FlowAnalyzer().analyzeTree(env, make);
    new CaptureAnalyzer().analyzeTree(env, make);
}
```

### # 脱糖(desugar)

```java
protected void desugar(final Env<AttrContext> env, Queue<Pair<Env<AttrContext>, JCClassDecl>> results) {
    // ...
    class ScanNested extends TreeScanner {
        protected boolean hasLambdas;
        // ...
        @Override
        public void visitLambda(JCLambda tree) {
            hasLambdas = true;
            super.visitLambda(tree);
        }
        // ..
    }
    ScanNested scanner = new ScanNested();
    scanner.scan(env.tree);
    for (Env<AttrContext> dep: scanner.dependencies) {
        if (!compileStates.isDone(dep, CompileState.FLOW))
            desugaredEnvs.put(dep, desugar(flow(attribute(dep))));
    }
    // ...
        if (source.allowLambda() && scanner.hasLambdas) {
            if (shouldStop(CompileState.UNLAMBDA))
                return;
            env.tree = LambdaToMethod.instance(context).translateTopLevelClass(env, env.tree, localMake);
            compileStates.put(env, CompileState.UNLAMBDA);
        }
    // ...
        //generate code for each class
        for (List<JCTree> l = cdefs; l.nonEmpty(); l = l.tail) {
            JCClassDecl cdef = (JCClassDecl)l.head;
            results.add(new Pair<Env<AttrContext>, JCClassDecl>(env, cdef));
        }
    //...
}
```

#### - 遍历JCTree(TreeScanner)

TreeScanner只是遍历整个JCTree并无实际意义：

```
// src/share/classes/com/sun/tools/javac/tree/TreeScanner.java
public void scan(JCTree tree) {
    if(tree!=null) tree.accept(this);
}

public void visitClassDef(JCClassDecl tree) {
    scan(tree.mods);
    scan(tree.typarams);
    scan(tree.extending);
    scan(tree.implementing);
    scan(tree.defs);
}
```

[![java-javac-compile2-desugar-TreeScanner-visitClassDef-Test.png](https://j.mp/2xo0dr6)](https://j.mp/2Q4i50Q)


JCTree$JCClassDecl(defs) ->
JCMethodDecl(body) ->
JCBlock(stats) ->
JCExpressionStatement(exec) ->
JCMethodInvocation(args) ->
JCLambda

这里会重新visitLambda用以标记是否存在lambda：

```java
// src/share/classes/com/sun/tools/javac/tree/TreeScanner.java
@Override
public void visitLambda(JCLambda tree) {
    hasLambdas = true;
    super.visitLambda(tree);
}

public void visitLambda(JCLambda tree) {
    scan(tree.body);
    scan(tree.params);
}
```

[![java-javac-compile2-desugar-TreeScanner-visitApply-JCMethodInvocation-args-JCLambda-Test.png](https://j.mp/2IB4YQn)](https://j.mp/2vW0tx6)

#### - Lambda翻译器(LambdaToMethod)

即这是一个将Lambda表达式转化(翻译成)成正常JCTree的方法。

```java
// src/share/classes/com/sun/tools/javac/comp/LambdaToMethod.java
public JCTree translateTopLevelClass(Env<AttrContext> env, JCTree cdef, TreeMaker make) {
    this.make = make;
    this.attrEnv = env;
    this.context = null;
    this.contextMap = new HashMap<JCTree, TranslationContext<?>>();
    return translate(cdef);
}
```

[![java-javac-compile2-desugar-LambdaToMethod-translateTopLevelClass-result.png](https://j.mp/2TGJkR3)](https://j.mp/2Q50lCz)
可以看到translate之后`tree.defs`多了一个`JCTree$JCMethodDecl@3400`，其函数如下：

```java
/*synthetic*/ private static void lambda$main$0(/*synthetic*/ final Test cap$0) {
    System.out.println("Test.funLambda invoked! name = " + cap$0.name);
}
```
这里使用synthetic标记，表示这是一个编译期生成的函数。其内容则完全是原先lambda表达式的body部分。
而原先的`JCTree$JCMethocDecl@2145`的第二个statement则由原先的lambda表达式变为:

```
t.funLambda(java.lang.invoke.LambdaMetafactory.metafactory(t));
```

这里就是运行时的过程了，最终通过[`LambdaMetafactory`](https://j.mp/2TXCwgZ)进行`buildCallSite` 找到 ` funLambda ` 对应的函数，及其参数函数。Java8运行时对Lambda的支持，暂略过。

### # 代码生成(generate)

TBC

## 问题

- <https://stackoverflow.com/questions/16626810/can-android-studio-be-used-to-run-standard-java-projects>

- <https://github.com/spotbugs/spotbugs/issues/931>

- [Javac 源码调试教程](https://juejin.im/post/5d22898be51d4555fc1acd15)

- [深入分析 Javac 编译原理](https://juejin.im/post/5b9fa2e5f265da0ad2217f84)

- [retrolambda](https://github.com/luontola/retrolambda)

- [java/lang/invoke/LambdaMetafactory.java](https://github.com/frohoff/jdk8u-jdk/blob/master/src/share/classes/java/lang/invoke/LambdaMetafactory.java)