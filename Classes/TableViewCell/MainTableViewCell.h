//
//  MainTableViewCell.h
//  dreaMote
//
//  Created by Moritz Venn on 08.03.08.
//  Copyright 2008-2011 Moritz Venn. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <TableViewCell/BaseTableViewCell.h>

/*!
 @brief Cell identifier for this cell.
 */
extern NSString *kMainCell_ID;

/*!
 @brief UITableViewCell optimized to display elements on MainViewController.
 */
@interface MainTableViewCell : BaseTableViewCell
{
@private
	NSDictionary	*_dataDictionary; /*!< @brief Item. */
}

/*!
 @brief Item.
 */
@property (nonatomic, strong) NSDictionary *dataDictionary;

@end
