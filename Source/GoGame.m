/*  This code is based on Apple's "GeekGameBoard" sample code, version 1.0.
    http://developer.apple.com/samplecode/GeekGameBoard/
    Copyright © 2007 Apple Inc. Copyright © 2008 Jens Alfke. All Rights Reserved.

    Redistribution and use in source and binary forms, with or without modification, are permitted
    provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice, this list of conditions
      and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice, this list of
      conditions and the following disclaimer in the documentation and/or other materials provided
      with the distribution.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
    IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND 
    FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRI-
    BUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
    (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR 
    PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
    CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF 
    THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/
#import "GoGame.h"
#import "Grid.h"
#import "Piece.h"
#import "Dispenser.h"
#import "Stack.h"
#import "QuartzUtils.h"
#import "GGBUtils.h"


@implementation GoGame


+ (int) dimensions {return 19;}

- (id) init
{
    self = [super init];
    if (self != nil) {
        [self setNumberOfPlayers: 2];
        [(Player*)[_players objectAtIndex: 0] setName: @"Red"];
        [(Player*)[_players objectAtIndex: 1] setName: @"White"];
    }
    return self;
}
        
- (void) setUpBoard
{
    int dimensions = [[self class] dimensions];
    CGSize size = _table.bounds.size;
    CGFloat boardSide = MIN(size.width,size.height);
    RectGrid *board = [[RectGrid alloc] initWithRows: dimensions columns: dimensions 
                                              frame: CGRectMake(floor((size.width-boardSide)/2),
                                                                floor((size.height-boardSide)/2),
                                                                boardSide,boardSide)];
    _board = board;
    /*
    grid.backgroundColor = GetCGPatternNamed(@"Wood.jpg");
    grid.borderColor = kTranslucentLightGrayColor;
    grid.borderWidth = 2;
    */
    board.lineColor = kTranslucentGrayColor;
    board.cellClass = [GoSquare class];
    [board addAllCells];
    ((GoSquare*)[board cellAtRow: 2 column: 2]).dotted = YES;
    ((GoSquare*)[board cellAtRow: 6 column: 6]).dotted = YES;
    ((GoSquare*)[board cellAtRow: 2 column: 6]).dotted = YES;
    ((GoSquare*)[board cellAtRow: 6 column: 2]).dotted = YES;
    board.usesDiagonals = board.allowsMoves = board.allowsCaptures = NO;
    [_table addSublayer: board];
    [board release];
    
    CGRect gridFrame = board.frame;
    CGFloat pieceSize = (int)board.spacing.width & ~1;  // make sure it's even
    CGFloat captureHeight = gridFrame.size.height-4*pieceSize;
    _captured[0] = [[Stack alloc] initWithStartPos: CGPointMake(2*pieceSize,0)
                                           spacing: CGSizeMake(0,pieceSize)
                                      wrapInterval: floor(captureHeight/pieceSize)
                                       wrapSpacing: CGSizeMake(-pieceSize,0)];
    _captured[0].frame = CGRectMake(CGRectGetMinX(gridFrame)-3*pieceSize, 
                                      CGRectGetMinY(gridFrame)+3*pieceSize,
                                      2*pieceSize, captureHeight);
    _captured[0].zPosition = kPieceZ+1;
    [_table addSublayer: _captured[0]];
    [_captured[0] release];
    
    _captured[1] = [[Stack alloc] initWithStartPos: CGPointMake(0,captureHeight)
                                           spacing: CGSizeMake(0,-pieceSize)
                                      wrapInterval: floor(captureHeight/pieceSize)
                                       wrapSpacing: CGSizeMake(pieceSize,0)];
    _captured[1].frame = CGRectMake(CGRectGetMaxX(gridFrame)+pieceSize, 
                                      CGRectGetMinY(gridFrame)+pieceSize,
                                      2*pieceSize, captureHeight);
    _captured[1].zPosition = kPieceZ+1;
    [_table addSublayer: _captured[1]];
    [_captured[1] release];

    PreloadSound(@"Pop");
}

- (CGImageRef) iconForPlayer: (int)playerNum
{
    return GetCGImageNamed( playerNum ?@"bot086.png" :@"bot089.png" );
}

- (Piece*) pieceForPlayer: (int)index
{
    NSString *imageName = index ?@"bot086.png" :@"bot089.png";
    CGFloat pieceSize = (int)(_board.spacing.width * 0.9) & ~1;  // make sure it's even
    Piece *stone = [[Piece alloc] initWithImageNamed: imageName scale: pieceSize];
    stone.owner = [self.players objectAtIndex: index];
    return [stone autorelease];
}

- (Bit*) bitToPlaceInHolder: (id<BitHolder>)holder
{
    if( holder.bit != nil || ! [holder isKindOfClass: [GoSquare class]] )
        return nil;
    else
        return [self pieceForPlayer: self.currentPlayer.index];
}


- (BOOL) canBit: (Bit*)bit moveFrom: (id<BitHolder>)srcHolder
{
    return (srcHolder==nil);
}


- (BOOL) canBit: (Bit*)bit moveFrom: (id<BitHolder>)srcHolder to: (id<BitHolder>)dstHolder
{
    if( srcHolder!=nil || ! [dstHolder isKindOfClass: [Square class]] )
        return NO;
    Square *dst=(Square*)dstHolder;
    
    // There should be a check here for a "ko" (repeated position) ... exercise for the reader!
    
    // Check for suicidal move. First an easy check for an empty adjacent space:
    NSArray *neighbors = dst.neighbors;
    for( GridCell *c in neighbors )
        if( c.empty )
            return YES;                     // there's an empty space
    // If the piece is surrounded, check the neighboring groups' liberties:
    for( GridCell *c in neighbors ) {
        int nLiberties;
        [c getGroup: &nLiberties];
        if( c.bit.unfriendly ) {
            if( nLiberties <= 1 )
                return YES;             // the move captures, so it's not suicidal
        } else {
            if( nLiberties > 1 )
                return YES;             // the stone joins a group with other liberties
        }
    }
    return NO;
}


- (void) bit: (Bit*)bit movedFrom: (id<BitHolder>)srcHolder to: (id<BitHolder>)dstHolder
{
    Square *dst=(Square*)dstHolder;
    int curIndex = self.currentPlayer.index;
    // Check for captured enemy groups:
    BOOL captured = NO;
    for( GridCell *c in dst.neighbors )
        if( c.bit.unfriendly ) {
            int nLiberties;
            NSSet *group = [c getGroup: &nLiberties];
            if( nLiberties == 0 ) {
                captured = YES;
                for( GridCell *capture in group )
                    [_captured[curIndex] addBit: capture.bit];  // Moves piece to POW camp!
            }
        }
    if( captured )
        PlaySound(@"Pop");
    
    [self.currentTurn addToMove: dst.name];
    [self endTurn];
}


// This sample code makes no attempt to detect the end of the game, or count score,
// both of which are rather complex to decide in Go.


#pragma mark -
#pragma mark STATE:


- (NSString*) stateString
{
    int n = _board.rows;
    unichar state[n*n];
    for( int y=0; y<n; y++ )
        for( int x=0; x<n; x++ ) {
            Bit *bit = [_board cellAtRow: y column: x].bit;
            unichar ch;
            if( bit==nil )
                ch = '-';
            else
                ch = '1' + bit.owner.index;
            state[y*n+x] = ch;
        }
    return [NSString stringWithCharacters: state length: n*n];
}

- (void) setStateString: (NSString*)state
{
    NSLog(@"Go: setStateString: '%@'",state);
    int n = _board.rows;
    for( int y=0; y<n; y++ )
        for( int x=0; x<n; x++ ) {
            int i = y*n+x;
            Piece *piece = nil;
            if( i < state.length ) {
                int index = [state characterAtIndex: i] - '1';
                if( index==0 || index==1 )
                    piece = [self pieceForPlayer: index];
            }
            [_board cellAtRow: y column: x].bit = piece;
        }
}


- (BOOL) applyMoveString: (NSString*)move
{
    NSLog(@"Go: applyMoveString: '%@'",move);
    return [self animatePlacementIn: [_board cellWithName: move]];
}


@end


@implementation Go9Game
+ (NSString*) displayName   {return @"Go (9x9)";}
+ (int) dimensions          {return 9;}
@end


@implementation Go13Game
+ (NSString*) displayName   {return @"Go (13x13)";}
+ (int) dimensions          {return 13;}
@end
