//
//  MVSFTPFileUpload.m
//  FileShuttle
//
//  Created by Michael Villar on 12/13/11.
//

#import "MVSFTPFileUpload.h"
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <sys/file.h>
#include <sys/ioctl.h>
#include <sys/param.h>
#include <sys/wait.h>
#include <sys/time.h>
#include <util.h>
#include "sshversion.h"

///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
@interface MVSFTPFileUpload ()

@property (assign) pid_t scppid;
@property (assign) int masterfd;

- (void)write:(char *)buf;
- (void)parseProgressOutputString:(NSString *)line;

@end

///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
@implementation MVSFTPFileUpload

extern int	errno;
extern char	**environ;
int sftpconnecting = 0;

@synthesize scppid		= scppid_,
            masterfd	= masterfd_;

///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Private Methods

///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)start {
	if([self.delegate respondsToSelector:@selector(fileUploadDidStartUpload:)])
		[self.delegate fileUploadDidStartUpload:self];
	
	[NSThread detachNewThreadSelector:@selector(startFromThread) toTarget:self withObject:nil];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
- (BOOL)execBlockingSSHExecutable:(char *)executable withArguments:(char **)execargs password:(char *)password
{
	char		ttyname[ MAXPATHLEN ];
	int			status;
	
	execargs[0] = executable;
	
  if ((self.scppid = forkpty( &masterfd_, ttyname, NULL, NULL ))) {
    if ( fcntl( self.masterfd, F_SETFL, O_NONBLOCK ) < 0 ) {	/* prevent master from blocking */
    }
		
		fd_set	readmask;
		unichar	buf[ MAXPATHLEN ];
		int     pwsent = 0, validpw = 0, noscp = 0, loading = 0, copying = 0;
		NSString *line;
		FILE		*mfp;
		
		if (( mfp = fdopen( self.masterfd, "r" )) == NULL ) {
			[self performSelectorOnMainThread:@selector(error:)
                             withObject:@"fdopen master fd returned NULL"
                          waitUntilDone:YES];
			return NO;
    }
		
    setvbuf( mfp, NULL, _IONBF, 0 );
		
		for ( ;; ) {
      NSAutoreleasePool	*pool = [[ NSAutoreleasePool alloc ] init ];
			FD_ZERO( &readmask );
      FD_SET( self.masterfd, &readmask );
      if ( select( self.masterfd + 1, &readmask, NULL, NULL, NULL ) < 0 ) {
				[self performSelectorOnMainThread:@selector(error:)
                               withObject:@"select() returned a value less than zero"
                            waitUntilDone:YES];
				return NO;
      }
      
      if ( FD_ISSET( self.masterfd, &readmask )) {
        if ( fgets(( char * )buf, MAXPATHLEN, mfp ) == NULL ) break;
        
				line = [NSString stringWithCString:(char*)buf encoding:NSASCIIStringEncoding];
				
        if (( strstr(( char * )buf, "Password:" ) != NULL
             || strstr(( char * )buf, "password:" ) != NULL
             || strstr(( char * )buf, "passphrase" ) != NULL )
            && !validpw ) {
					// Send password
					[self write:password];
          pwsent = 1;
        }
				else if ( strchr(( char * )buf, '%' ) != NULL ) {
					loading += 1;
					// Loading informations
          if ( ! copying ) {
            copying = 1;
          } else {
            [ self parseProgressOutputString: line];
          }
        }
				else {
					if([line length] > 5 && loading == 0) {
						[self performSelectorOnMainThread:@selector(error:)
                                   withObject:line
                                waitUntilDone:YES];
						return NO;
					}
				}
        
        memset(( char * )buf, '\0', strlen(( char * )buf ));
        [ pool release ];
        if ( noscp ) break;
      }
    }
		
		if ( fclose( mfp ) != 0 ) {
			NSLog(@"fclose failed: %s", strerror( errno ));
		}
		( void )close( self.masterfd );
				
		self.scppid = wait( &status );
				
    if ( WIFEXITED( status )) {
      // Normal exit
    } else if ( WIFSIGNALED( status )) {
      NSLog(@"Exit with signal = %d\n", status);
			return NO;
    } else if ( WIFSTOPPED( status )) {
			NSLog(@"WIFSTOPPED\n");
			return NO;
    }
    
    self.scppid = 0;
		
		return YES;
  } else if ( self.scppid < 0 ) {
    NSLog( @"forkpty failed: %s", strerror( errno ));
  } else {
    execve( executable, ( char ** )execargs, environ );
		[self performSelectorOnMainThread:@selector(error:)
                           withObject:@"execve failed"
                        waitUntilDone:YES];
  }
	
	return NO;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
- (BOOL)execBlockingExecutable:(char *)executable withArguments:(char **)execargs password:(char *)password followedByCommand: (char *)command
{
    char		ttyname[ MAXPATHLEN ];
    int			status;
    
    execargs[0] = executable;
    
    if ((self.scppid = forkpty( &masterfd_, ttyname, NULL, NULL ))) {
        if ( fcntl( self.masterfd, F_SETFL, O_NONBLOCK ) < 0 ) {	/* prevent master from blocking */
        }
        
        fd_set	readmask;
        unichar	buf[ MAXPATHLEN ];
        int     pwsent = 0, validpw = 0, noscp = 0, loading = 0, copying = 0, uploading = 0;
        NSString *line;
        FILE		*mfp;
        
        if (( mfp = fdopen( self.masterfd, "r" )) == NULL ) {
            [self performSelectorOnMainThread:@selector(error:)
                                   withObject:@"fdopen master fd returned NULL"
                                waitUntilDone:YES];
            return NO;
        }
        
        setvbuf( mfp, NULL, _IONBF, 0 );
        
        for ( ;; ) {
            NSAutoreleasePool	*pool = [[ NSAutoreleasePool alloc ] init ];
            FD_ZERO( &readmask );
            FD_SET( self.masterfd, &readmask );
            if ( select( self.masterfd + 1, &readmask, NULL, NULL, NULL ) < 0 ) {
                [self performSelectorOnMainThread:@selector(error:)
                                       withObject:@"select() returned a value less than zero"
                                    waitUntilDone:YES];
                return NO;
            }
            
            if ( FD_ISSET( self.masterfd, &readmask )) {
                if ( fgets(( char * )buf, MAXPATHLEN, mfp ) == NULL ) break;
                
                line = [NSString stringWithCString:(char*)buf encoding:NSASCIIStringEncoding];
                
                if (( strstr(( char * )buf, "Password:" ) != NULL
                     || strstr(( char * )buf, "password:" ) != NULL
                     || strstr(( char * )buf, "passphrase" ) != NULL )
                    && !validpw ) {
                    // Send password
                    [self write:password];
                    pwsent = 1;
                }
                else if ( strchr(( char * )buf, '%' ) != NULL ) {
                    loading += 1;
                    // Loading informations
                    NSLog(@"uploading...");
                    if ( ! copying ) {
                        copying = 1;
                    } else {
                        [ self parseProgressOutputString: line];
                    }
                }
                
                else if (( strstr(( char * )buf, "Connected to" ) != NULL )
                         || strstr(( char * )buf, "Changing to:" ) != NULL ) {
                    //wait for sftp prompt
                    NSLog(@"logged in, wait for sftp prompt");
                }
                else if ( strstr(( char * )buf, "sftp>" ) != NULL ) {
                    if (!uploading) {
                        [self write:command];
                        uploading = 1;
                        NSLog(@"starting upload");
                    }
                    else {
                        NSLog(@"upload complete, exit");
                        [self write: "exit"];
                        //return TRUE
                    }
                }
                else if (( strstr(( char * )buf, command ) != NULL
                       //   || strstr(( char * )buf, (char*)[[self.source path] UTF8String] ) != NULL
                     || strstr(( char * )buf, "Uploading" ) != NULL )) {
                    //wait for upload to start
                    NSLog(@"wait for upload to start");
                }
                else {
                    if([line length] > 5 && loading == 0) {
                        [self performSelectorOnMainThread:@selector(error:)
                                               withObject:line
                                            waitUntilDone:YES];
                        return NO;
                    }
                }
                
                memset(( char * )buf, '\0', strlen(( char * )buf ));
                [ pool release ];
                if ( noscp ) break;
            }
        }
        
        if ( fclose( mfp ) != 0 ) {
            NSLog(@"fclose failed: %s", strerror( errno ));
        }
        ( void )close( self.masterfd );
        
        self.scppid = wait( &status );
        
        if ( WIFEXITED( status )) {
            // Normal exit
            NSLog(@"Normal exit");
        } else if ( WIFSIGNALED( status )) {
            NSLog(@"Exit with signal = %d\n", status);
            return NO;
        } else if ( WIFSTOPPED( status )) {
            NSLog(@"WIFSTOPPED\n");
            return NO;
        }
        
        self.scppid = 0;
        
        return YES;
    } else if ( self.scppid < 0 ) {
        NSLog( @"forkpty failed: %s", strerror( errno ));
    } else {
        execve( executable, ( char ** )execargs, environ );
        [self performSelectorOnMainThread:@selector(error:)
                               withObject:@"execve failed"
                            waitUntilDone:YES];
    }
    
    return NO;
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)startFromThread {
	NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	
	NSURL *url = [NSURL URLWithString:self.destination];
	NSString *path = url.relativePath;
	path = [path stringByReplacingOccurrencesOfString:@" " withString:@"\\ "];
    NSURL * uploadurl = [url URLByDeletingLastPathComponent];
    NSString *uploadpath = uploadurl.relativePath;
    uploadpath = [uploadpath stringByReplacingOccurrencesOfString:@" " withString:@"\\ "];
	NSString *userathostString = [NSString stringWithFormat:@"%@@%@:%@",
                                self.username, url.host, uploadpath];
	char* userathost = (char*)[userathostString UTF8String];
	char* password = (char*)[self.password UTF8String];
	int portnumber = [url.port intValue];
    NSString *command = [NSString stringWithFormat: @"put %@", [self.source path]];
    char* putlocalfilecommand = (char*)[command UTF8String];
	
  char		executable[ MAXPATHLEN ], *execargs[ 7 ];
	char    chmodExecutable[ MAXPATHLEN ], chmodPermissions[ 256 ], *chmodargs[ 6 ];
  NSString *sftpBinary;
	
	sftpBinary = @"/usr/bin/sftp";
  strcpy( executable, [ sftpBinary UTF8String ] );
  execargs[ 0 ] = executable;
	
  sftpconnecting = 1;
	
	char* portarg = (char*)[[[NSNumber numberWithInt:portnumber]stringValue]UTF8String];
	
  //execargs[ 1 ] = "-r";
  //	execargs[ 1 ] = "-q";
  execargs[ 1 ] = "-P";
  execargs[ 2 ] = portarg;
  execargs[ 3 ] = userathost;
  execargs[ 4 ] = NULL;
	
  char		put[ MAXPATHLEN ], *putargs[ 3 ];
  NSString *putBinary = @"put";
  strcpy( put, [ putBinary UTF8String ] );
  putargs[ 0 ] = put;
  putargs[ 1 ] = (char*)[[self.source path] UTF8String];
  putargs[ 2 ] = NULL;
    
	if (self.changePermissions) {
		NSString *sshBinary = @"/usr/bin/ssh";
		strcpy(chmodExecutable, [sshBinary UTF8String]);
		
		strncpy(chmodPermissions, [self.permissionString UTF8String], 256);
		
		NSString *servernameString = [NSString stringWithFormat:@"%@@%@",
																	self.username, url.host];
		char* servername = (char*)[servernameString UTF8String];
		
		NSString *filenameString = path;
		char* filename = (char*)[filenameString UTF8String];
		
		chmodargs[ 0 ] = chmodExecutable;
		chmodargs[ 1 ] = servername;
		chmodargs[ 2 ] = "chmod";
		chmodargs[ 3 ] = chmodPermissions;
		chmodargs[ 4 ] = filename;
		chmodargs[ 5 ] = NULL;		
	}
	
    BOOL sftpStatus = [self execBlockingExecutable:executable withArguments:execargs password:password followedByCommand: putlocalfilecommand];
	if (!sftpStatus) {
		[pool release];
		return;
	}
	
	if (self.changePermissions)
	{
		BOOL sshStatus = [self execBlockingSSHExecutable:chmodExecutable withArguments:chmodargs password:password];
		if (!sshStatus) {
			[pool release];
			return;
		}
	}
	
	[pool release];
	
	if([self.delegate respondsToSelector:@selector(fileUploadDidSuccess:)])
		[self.delegate performSelectorOnMainThread:@selector(fileUploadDidSuccess:)
                                    withObject:self
                                 waitUntilDone:NO];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)error:(NSString*)error {
	if([self.delegate respondsToSelector:@selector(fileUpload:didFailWithError:)])
		[self.delegate fileUpload:self
             didFailWithError:error];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)write:(char *)buf
{
  int	wr;
  if (( wr = write( self.masterfd, buf, strlen( buf ))) != strlen( buf ))
	{
		[self performSelectorOnMainThread:@selector(error:)
                           withObject:@"error"
                        waitUntilDone:YES];
		return;
	}
  if (( wr = write( self.masterfd, "\n", strlen( "\n" ))) != strlen( "\n" ))
	{
		[self performSelectorOnMainThread:@selector(error:)
                           withObject:@"error"
                        waitUntilDone:YES];
		return;
	}
}

///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)parseProgressOutputString:(NSString *)line
{
    NSLog(@"parseProgressOutputString : %@", line);
	if ([self.delegate respondsToSelector:@selector(fileUpload:didChangeProgression:
                                                  bytesRead:totalBytes:)])
	{
		NSString *percent = nil;
		BOOL matched = [line getCapturesWithRegexAndReferences:@"( *)([0-9]*)%( *)", @"${2}",
                    &percent, nil];
		
		if(matched) {
			[self.delegate fileUpload:self
           didChangeProgression:[percent floatValue] / 100
                      bytesRead:-1
                     totalBytes:-1];
		}
	}
}

@end
