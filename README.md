# macintora
A MacOS native IDE tool for Oracle Database developers

## Building from source
Macintora depends on a few other projects, some of which are required, and some optional.

### Dependencies
- Oracle [Instant Client](https://www.oracle.com/database/technologies/instant-client/macos-intel-x86-downloads.html). Only x86 version is available for MacOS at the time of writing. Hence, we're limited with Rosetta version of Macintora.
- [OCILIB](https://github.com/vrogier/ocilib). More on how to build the library below.  
- [SwiftOracle](https://github.com/iliasaz/SwiftOracle).   
- [CodeEditor](https://github.com/iliasaz/CodeEditor).   
- [SF Mono Font](https://devimages-cdn.apple.com/design/resources/download/SF-Mono.dmg)  
- If you would like to have formatter capability, consider building a Graal executable as described in [Trivadis PL/SQL & SQL Formatter Settings](https://github.com/Trivadis/plsql-formatter-settings#plsql--sql-formatter-settings). 

## Installing the binary
Macintora binary is built for MacOS 12.3+, x86 platform. The binary needs the following libraries to be installed on the target machine.

### Dependencies
- Oracle [Instant Client](https://www.oracle.com/database/technologies/instant-client/macos-intel-x86-downloads.html). Only x86 version is available for MacOS at the time of writing. Hence, we're limited with Rosetta version of Macintora.
- [OCILIB](https://github.com/vrogier/ocilib). More on how to build the library below.
- [SF Mono Font](https://devimages-cdn.apple.com/design/resources/download/SF-Mono.dmg).     
- If you would like to have formatter capability, consider building a Graal executable as described in [Trivadis PL/SQL & SQL Formatter Settings](https://github.com/Trivadis/plsql-formatter-settings#plsql--sql-formatter-settings). 

## Building OCILIB from sources
- Make sure to download Oracle Instant Client with SDK package.  
- Set ORACLE_HOME environment variable to point to Instant Client directory.  
- Execute the following. This will produce some output, but there should not be errors. If you're on Apple Silicon CPU, make sure to include "arch -x86" to build the library for x86 platform.
```
git clone https://github.com/vrogier/ocilib.git  
cd ocilib
chmod +x configure
arch -x86_64 ./configure --with-oracle-import=runtime --with-oracle-headers-path=$ORACLE_HOME/sdk/include --with-oracle-lib-path=$ORACLE_HOME --disable-dependency-tracking
arch -x86_64 make
arch -x86_64 sudo make install
ls -la /usr/local/lib
```
- The last output above should display "liboci" library.  

## Other projects used - directly or as an inspiration 
- [SwiftOracle](https://github.com/goloveychuk/SwiftOracle)  
- [OCILIB](https://github.com/vrogier/ocilib)  
- [CodeEditor](https://github.com/iliasaz/CodeEditor)  
- [Line Number Gutter Text View](https://github.com/raphaelhanneken/line-number-text-view)  
- [SwiftUIWindow](https://github.com/mortenjust/SwiftUIWindow)  
- [Trivadis PL/SQL & SQL Formatter Settings](https://github.com/Trivadis/plsql-formatter-settings#plsql--sql-formatter-settings)

