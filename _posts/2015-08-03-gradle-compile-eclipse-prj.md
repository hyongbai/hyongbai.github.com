---
layout: post
title: "使用gradle编译Eclipse工程-AndroidStudio导入Eclipse"
category: all-about-tech
tags: 
- gradle
- eclipse

date: 2015-08-03 17:50:24+08:00
--- 

### 扯扯淡

Android Studio越来越好用了，以至于本来用的IntelliJ都觉得不够给力了。因此公司决定迁移到Android Studio上面。但是问题来了，虽然可以将其导入进来自动变成gradle style，但是如果使用AndroidStudio自带的目录结构的话，之前的提交记录全部都乱了。

因此，就有了迁移到gradle但是不变目录结构的需求了。


### 不啰嗦，直接上结果

- 第一步，可以先创建一个Android Studio工程。

- 第二步，把`.gradle/`、`gradle/`、`gradlew`、`gradlew.bat`、`build.gradle`拷贝到工程根目录。

- 第三步，打开`build.gradle`并添加如下内容:<br/-

```groovy
buildscript {
    repositories {
        jcenter()
    }
    dependencies {
        classpath 'com.android.tools.build:gradle:1.2.3'
    }
}

allprojects {
    repositories {
        jcenter()
    }
}

apply plugin: 'com.android.application'

android {
    compileSdkVersion 22
    buildToolsVersion "23.0.0 rc2"

    defaultConfig {
        applicationId "com.alensw.PicFolder"
        minSdkVersion 5
        targetSdkVersion 22
        versionCode 159
        versionName "4.5.2"

        testApplicationId "com.alensw.PicFolder.tests"
        testInstrumentationRunner "android.test.InstrumentationTestRunner"
    }
    
    lintOptions {
        abortOnError false
    }

    sourceSets {
        main {
            manifest.srcFile 'AndroidManifest.xml'
            java.srcDirs = ['src']
            resources.srcDirs = ['src']
            aidl.srcDirs = ['src']
            renderscript.srcDirs = ['src']
            res.srcDirs = ['res']
            assets.srcDirs = ['assets']
            jniLibs.srcDirs = ['libs']
        }

        androidTest.setRoot('tests')
    }
}

dependencies {
    compile fileTree(dir: 'libs', include: ['*.jar'])
}
```

- 第四步，根据自己的项目情况将`builder.gradle`中的`applicationId`,`testApplicationId`等更改成自己所需要的。

- 最后，在AndroidStudio中打开刚刚的工程。编译，运行成功。

需要注意的是，记得在`.gitignore`里面添加如下内容以免给别人带来不必要的麻烦:<br/-

```yml
.gradle
build/
 
# Ignore Gradle GUI config
gradle-app.setting

# Avoid ignoring Gradle wrapper jar file (.jar files are usually ignored)
!gradle-wrapper.jar
```
