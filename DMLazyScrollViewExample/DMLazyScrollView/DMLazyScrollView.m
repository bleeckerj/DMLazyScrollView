//
//  DMLazyScrollView.m
//  Lazy Loading UIScrollView for iOS
//
//  Created by Daniele Margutti (me@danielemargutti.com) on 24/11/12.
//  Copyright (c) 2012 http://www.danielemargutti.com. All rights reserved.
//  Distribuited under MIT License
//

#import "DMLazyScrollView.h"

#define kDMLazyScrollViewTransitionDuration     0.4

@interface DMLazyScrollView() <UIScrollViewDelegate> {
    NSUInteger      numberOfPages;
    NSUInteger      currentPage;
    BOOL            isManualAnimating;
}

@end

@implementation DMLazyScrollView

@synthesize numberOfPages,currentPage;
@synthesize dataSource,controlDelegate;

- (id)init {
    return [self initWithFrame:CGRectZero];
}

- (id)initWithFrame:(CGRect)frame
{
    return [self initWithFrameAndDirection:frame direction:DMLazyScrollViewDirectionHorizontal];
}

- (id)initWithFrameAndDirection:(CGRect)frame direction:(DMLazyScrollViewDirection)direction
{
    self = [super initWithFrame:frame];
    if (self) {
        _direction = direction;
        [self initializeControl];
    }
    return self;
}

- (void) awakeFromNib {
    [self initializeControl];
}

- (void) initializeControl {
    self.showsHorizontalScrollIndicator = NO;
    self.showsVerticalScrollIndicator = NO;
    self.pagingEnabled = YES;
    self.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    
    if (_direction == DMLazyScrollViewDirectionHorizontal) {
        self.contentSize = CGSizeMake(self.frame.size.width*5.0f, self.frame.size.height);
    } else {
        self.contentSize = CGSizeMake(self.frame.size.width, self.frame.size.height*5.0f);
        
    }
    self.delegate = self;
    
    currentPage = NSNotFound;
}

- (void) setNumberOfPages:(NSUInteger)pages {
    if (pages != numberOfPages) {
        numberOfPages = pages;
        [self reloadData];
    }
}

- (void) reloadData {
    [self setCurrentViewController:0];
}

- (void) layoutSubviews {
    [super layoutSubviews];
}

- (CGRect) visibleRect {
    CGRect visibleRect;
    visibleRect.origin = self.contentOffset;
    visibleRect.size = self.bounds.size;
    return visibleRect;
}

- (CGPoint) createPoint:(CGFloat) size {
    if (_direction == DMLazyScrollViewDirectionHorizontal) {
        return CGPointMake(size, 0);
    } else {
        return CGPointMake(0, size);
    }
}

- (void) scrollViewDidScroll:(UIScrollView *)scrollView {
    if (isManualAnimating) return;
    
    CGFloat offset = (_direction==DMLazyScrollViewDirectionHorizontal) ? scrollView.contentOffset.x : scrollView.contentOffset.y;
    CGFloat size =(_direction==DMLazyScrollViewDirectionHorizontal) ? self.frame.size.width : self.frame.size.height;
    
    // with two pages only scrollview you can only go forward
    // (this prevents us to have a glitch with the next UIView (it can't be placed in two positions at the same time)
    if (self.numberOfPages == 2 && offset <= (size*2))
        [self setContentOffset: [self createPoint:size*2]];
    
    NSInteger newPageIndex = currentPage;
    
    if (offset <= size)
        newPageIndex = [self pageIndexByAdding:-1 from:currentPage];
    else if (offset >= (size*3))
        newPageIndex = [self pageIndexByAdding:+1 from:currentPage];
    
    [self setCurrentViewController:newPageIndex];
    
    // alert delegate
    if (nil != controlDelegate && [controlDelegate respondsToSelector:@selector(lazyScrollViewDidScroll:at:)])
        [controlDelegate lazyScrollViewDidScroll:self at:[self visibleRect].origin];
}

- (void) setCurrentViewController:(NSInteger) index {
    if (index == currentPage) return;
    currentPage = index;
    
    [self.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    NSInteger prevPage = [self pageIndexByAdding:-1 from:currentPage];
    NSInteger nextPage = [self pageIndexByAdding:+1 from:currentPage];
    
    [self loadControllerAtIndex:prevPage andPlaceAtIndex:-1];   // load previous page
    [self loadControllerAtIndex:index andPlaceAtIndex:0];       // load current page
    [self loadControllerAtIndex:nextPage andPlaceAtIndex:1];   // load next page
    
    CGFloat size =(_direction==DMLazyScrollViewDirectionHorizontal) ? self.frame.size.width : self.frame.size.height;
    
    self.contentOffset = [self createPoint:size*2.]; // recenter
}

- (UIViewController *) visibleViewController {
    __block UIView *visibleView = nil;
    [self.subviews enumerateObjectsUsingBlock:^(UIView *subView, NSUInteger idx, BOOL *stop) {
        if (CGRectIntersectsRect([self visibleRect], subView.frame)) {
            visibleView = subView;
            *stop = YES;
        }
    }];
    if (visibleView == nil) return nil;
    return [self viewControllerFromView:visibleView];
}

- (UIViewController *) viewControllerFromView:(UIView*) targetView {
    return (UIViewController *)[self traverseResponderChainForUIViewController:targetView];
}

- (id) traverseResponderChainForUIViewController:(UIView *) targetView {
    id nextResponder = [targetView nextResponder];
    if ([nextResponder isKindOfClass:[UIViewController class]]) {
        return nextResponder;
    } else if ([nextResponder isKindOfClass:[UIView class]]) {
        return [nextResponder traverseResponderChainForUIViewController:targetView];
    } else {
        return nil;
    }
}

- (NSInteger) pageIndexByAdding:(NSInteger) offset from:(NSInteger) index {
    // Complicated stuff with negative modulo
    while (offset<0) offset += numberOfPages;
    return (numberOfPages+index+offset) % numberOfPages;

}

- (void) moveByPages:(NSInteger) offset animated:(BOOL) animated {
    NSUInteger finalIndex = [self pageIndexByAdding:offset from:self.currentPage];
    DMLazyScrollViewTransition transition = (offset >= 0 ?  DMLazyScrollViewTransitionForward :
                                             DMLazyScrollViewTransitionBackward);
    [self setPage:finalIndex transition:transition animated:animated];
}

- (void) setPage:(NSInteger) newIndex animated:(BOOL) animated {
    [self setPage:newIndex transition:DMLazyScrollViewTransitionForward animated:animated];
}

- (void) setPage:(NSInteger) newIndex transition:(DMLazyScrollViewTransition) transition animated:(BOOL) animated {
    if (newIndex == currentPage) return;
    
    if (animated) {
        BOOL isOnePageMove = (abs(self.currentPage-newIndex) == 1);
        CGPoint finalOffset;
        
        if (transition == DMLazyScrollViewTransitionAuto) {
            if (newIndex > self.currentPage) transition = DMLazyScrollViewTransitionForward;
            else if (newIndex < self.currentPage) transition = DMLazyScrollViewTransitionBackward;
        }
        
        CGFloat size =(_direction==DMLazyScrollViewDirectionHorizontal) ? self.frame.size.width : self.frame.size.height;
        
        if (transition == DMLazyScrollViewTransitionForward) {
            if (!isOnePageMove)
                [self loadControllerAtIndex:newIndex andPlaceAtIndex:2];
            
            
            finalOffset = [self createPoint:(size*(isOnePageMove ? 3 : 4))];
        } else {
            if (!isOnePageMove)
                [self loadControllerAtIndex:newIndex andPlaceAtIndex:-2];
            
            finalOffset = [self createPoint:(size*(isOnePageMove ? 1 : 0))];
        }
        isManualAnimating = YES;
        
        [UIView animateWithDuration:kDMLazyScrollViewTransitionDuration
                              delay:0.0
                            options:UIViewAnimationCurveEaseOut
                         animations:^{
                             self.contentOffset = finalOffset;
                         } completion:^(BOOL finished) {
                             if (!finished) return;
                             [self setCurrentViewController:newIndex];
                             isManualAnimating = NO;
                         }];
    } else {
        [self setCurrentViewController:newIndex];
    }
}

- (void) setCurrentPage:(NSUInteger)newCurrentPage {
    [self setCurrentViewController:newCurrentPage];
}

- (UIViewController *) loadControllerAtIndex:(NSInteger) index andPlaceAtIndex:(NSInteger) destIndex {
    UIViewController *viewController = dataSource(index);
    viewController.view.tag = 0;
    
    if (_direction == DMLazyScrollViewDirectionHorizontal) {
        viewController.view.frame = CGRectMake(self.frame.size.width*(destIndex+2),
                                               0,
                                               self.frame.size.width,
                                               self.frame.size.height);
    } else {
        viewController.view.frame = CGRectMake(0,
                                               self.frame.size.height*(destIndex+2),
                                               self.frame.size.width,
                                               self.frame.size.height);
        
    }
    [self addSubview:viewController.view];
    return viewController;
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (nil != controlDelegate && [controlDelegate respondsToSelector:@selector(lazyScrollViewDidEndDragging:)])
        [controlDelegate lazyScrollViewDidEndDragging:self];
}

- (void)scrollViewWillBeginDecelerating:(UIScrollView *)scrollView {
    if (nil != controlDelegate && [controlDelegate respondsToSelector:@selector(lazyScrollViewWillBeginDecelerating:)])
        [controlDelegate lazyScrollViewWillBeginDecelerating:self];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (nil != controlDelegate && [controlDelegate respondsToSelector:@selector(lazyScrollViewDidEndDecelerating:atPageIndex:)])
        [controlDelegate lazyScrollViewDidEndDecelerating:self atPageIndex:self.currentPage];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if (nil != controlDelegate && [controlDelegate respondsToSelector:@selector(lazyScrollViewWillBeginDragging:)])
        [controlDelegate lazyScrollViewWillBeginDragging:self];
}


@end
