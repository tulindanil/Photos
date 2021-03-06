//
//  ViewController.m
//  Photos
//
//  Created by Danil Tulin on 11/16/16.
//  Copyright © 2016 Daniil Tulin. All rights reserved.
//

#import "AlbumsController.h"

#import <Photos/Photos.h>

#import "ImageManager.h"

#import "AlbumCell.h"
#import "PhotosController.h"

@interface AlbumsController () <PHPhotoLibraryChangeObserver>

@property (nonatomic) PHFetchResult<PHAssetCollection *> *albumsFetchResult;
@property (nonatomic) ImageManager *manager;

@end

@implementation AlbumsController

- (instancetype)init {
    if (self = [super init]) {
        [self.tableView registerClass:[AlbumCell class]
               forCellReuseIdentifier:ALBUM_CELL_ID];
    }
    return self;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:self];
}

#pragma mark - Table View Delegate

- (NSInteger)tableView:(UITableView *)tableView
 numberOfRowsInSection:(NSInteger)section {
    return self.albumsFetchResult.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    AlbumCell *cell = [tableView dequeueReusableCellWithIdentifier:ALBUM_CELL_ID
                                                      forIndexPath:indexPath];

    NSInteger index = indexPath.row;
    PHAssetCollection *collection = self.albumsFetchResult[index];

    cell.textLabel.text = collection.localizedTitle;
    cell.detailTextLabel.text = nil;
    cell.thumbnail = nil;
    
    executeInBackground(^{
        NSInteger count = [self fetchAssetCount:collection];
        executeInMain(^{
            cell.detailTextLabel.text = [[NSNumber numberWithInteger:count] stringValue];
        });
    });
    
    ImageResultHandler handler = ^void(UIImage *image) {
        cell.thumbnail = image;
    };
    [self.manager fetchImageAtIndex:index
                        withHandler:handler];
    return cell;
}

- (void)tableView:(UITableView *)tableView
didEndDisplayingCell:(AlbumCell *)cell
forRowAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger index = indexPath.row;
    [self.manager cancelImageFetchingAtIndex:index];
}

- (CGFloat)tableView:(UITableView *)tableView
heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return THUMBNAIL_SIZE.height + 2*OFFSET;
}

- (void)tableView:(UITableView *)tableView
didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PHAssetCollection *assetCollection = self.albumsFetchResult[indexPath.row];
    PhotosController *controller = [PhotosController
                                    photosControllerWithAssetCollection:assetCollection];
    controller.title = assetCollection.localizedTitle;
    [self.navigationController pushViewController:controller
                                         animated:YES];
}

#pragma mark - Fetching

- (NSArray *)lastAlbumAssets {
    NSMutableArray *assets = [NSMutableArray array];
    for (PHAssetCollection *collection in self.albumsFetchResult) {
        PHAsset *lastAsset = [self lastAssetForCollection:collection];
        [assets addObject:lastAsset];
    }
    return assets;
}

- (PHAsset *)lastAssetForCollection:(PHAssetCollection *)collection {
    PHFetchOptions *options = [[PHFetchOptions alloc] init];
    options.fetchLimit = 1;
    options.predicate = [NSPredicate predicateWithFormat:@"mediaType == %d", PHAssetMediaTypeImage];
    NSSortDescriptor *dateSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"creationDate"
                                                                       ascending:NO];
    options.sortDescriptors = @[dateSortDescriptor];
    AssetFetchResult *fetchResult = [PHAsset fetchAssetsInAssetCollection:collection
                                                                  options:options];
    PHAsset *lastAsset = [fetchResult firstObject];
    return lastAsset;
}

#pragma mark - Image Manager

- (ImageManager *)manager {
    if (_manager)
        return _manager;
    NSArray *assets = [self lastAlbumAssets];

    float width = 3 * THUMBNAIL_SIZE.width;

    CGSize size = CGSizeMake(width, width);
    _manager = [ImageManager managerWithAssets:assets
                                  andImageSize:size];
    return _manager;
}

#pragma mark - <PHPhotoLibraryChangeObserver>

- (void)photoLibraryDidChange:(PHChange *)changeInstance {
    PHFetchResultChangeDetails *changeDetails =
    							[changeInstance changeDetailsForFetchResult:self.albumsFetchResult];
    executeInMain(^{
        if (changeDetails != nil)
            [self updateContentWithChangeDetails:changeDetails];
        else
            [self.tableView reloadData];
    });
}

- (void)updateContentWithChangeDetails:(PHFetchResultChangeDetails *)changeDetails {
    _albumsFetchResult = changeDetails.fetchResultAfterChanges;
    if (changeDetails.hasIncrementalChanges)
        [self updateContentWithIncrementalChanges:changeDetails];
    else
        [self.tableView reloadData];
}

- (void)updateContentWithIncrementalChanges:(PHFetchResultChangeDetails *)changeDetails {
    [self.tableView beginUpdates];

    NSIndexSet *removed = changeDetails.removedIndexes;
    if (removed.count)
        [self.tableView deleteRowsAtIndexPaths:indexPathsFromIndexSet(removed)
                                        withRowAnimation:UITableViewRowAnimationFade];

    NSIndexSet *inserted = changeDetails.insertedIndexes;
    if (inserted.count)
        [self.tableView insertRowsAtIndexPaths:indexPathsFromIndexSet(inserted)
                                        withRowAnimation:UITableViewRowAnimationFade];

    NSIndexSet *changed = changeDetails.changedIndexes;
    if (changed.count)
        [self.tableView reloadRowsAtIndexPaths:indexPathsFromIndexSet(changed)
                                        withRowAnimation:UITableViewRowAnimationFade];

    if (changeDetails.hasMoves)
        [changeDetails enumerateMovesWithBlock:^(NSUInteger fromIndex, NSUInteger toIndex) {
                NSIndexPath *fromIndexPath = [NSIndexPath indexPathForItem:fromIndex inSection:0];
                NSIndexPath *toIndexPath = [NSIndexPath indexPathForItem:toIndex inSection:0];
                [self.tableView moveRowAtIndexPath:fromIndexPath		
                                                     toIndexPath:toIndexPath];		
        }];
    
    [self.tableView endUpdates];		
}

#pragma mark - FetchingResult

- (NSUInteger)fetchAssetCount:(PHAssetCollection *)assetCollection {
    PHFetchOptions *options = [[PHFetchOptions alloc] init];
    options.predicate = [NSPredicate predicateWithFormat:@"mediaType == %d", PHAssetMediaTypeImage];
    AssetFetchResult *fetchResult = [PHAsset fetchAssetsInAssetCollection:assetCollection
                                                                  options:options];
    return fetchResult.count;
}

- (PHFetchResult<PHAssetCollection *> *)albumsFetchResult {
    if (_albumsFetchResult)
        return _albumsFetchResult;

    PHAssetCollectionType type = PHAssetCollectionTypeAlbum;
    PHAssetCollectionSubtype subtype = PHAssetCollectionSubtypeAny;

    PHFetchOptions *options = [[PHFetchOptions alloc] init];
    _albumsFetchResult = [PHAssetCollection fetchAssetCollectionsWithType:type
                                                                  subtype:subtype
                                                                  options:options];
    return _albumsFetchResult;
}

@end
