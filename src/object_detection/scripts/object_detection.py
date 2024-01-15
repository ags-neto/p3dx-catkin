#!/usr/bin/env python

import rospy
import csv
import cv2

from message_filters import ApproximateTimeSynchronizer, Subscriber
from darknet_ros_msgs.msg import BoundingBoxes
from sensor_msgs.msg import Image
from nav_msgs.msg import Odometry

from cv_bridge import CvBridge


def calc_center(xmin, xmax, ymin, ymax):
    
    x0 = (xmin + xmax)/2
    y0 = (ymin + ymax)/2
    
    return [x0, y0]

def calc_centroid(xmin, xmax, ymin, ymax):
    
    dx = abs(xmax - xmin)
    dy = abs(ymax - ymin)
    
    [x0, y0] = calc_center(xmin, xmax, ymin, ymax)
    
    c_xmin = x0 - dx/4
    c_xmax = x0 + dx/4
    c_ymin = y0 - dy/4
    c_ymax = y0 + dy/4
    
    return c_xmin, c_xmax, c_ymin, c_ymax
    
def new_object(box, image, odom):
    
    FLAG = False
    
    b_xmin, b_xmax, b_ymin, b_ymax = calc_centroid(box.xmin, box.xmax, box.ymin, box.ymax)
    x0, y0 = calc_center(box.xmin, box.xmax, box.ymin, box.ymax)
    
    rospy.loginfo("%s: %f, %f", box.Class, x0, y0)
    
    with open("/home/ryken/Desktop/real/src/object_detection/buffer/buffer.csv") as file_in:
        reader = csv.reader(file_in.readlines())
        
    with open("/home/ryken/Desktop/real/src/object_detection/buffer/buffer.csv", "w") as file_out:
        writer = csv.writer(file_out)
        
        for row in reader:
            
            if box.Class == row[0]:
                
                x0, y0 = calc_center(box.xmin, box.xmax, box.ymin, box.ymax)
                c_xmin, c_xmax, c_ymin, c_ymax = float(row[1]), float(row[2]), float(row[3]), float(row[4])
                
                if x0 < c_xmax and x0 > c_xmin and y0 < c_ymax and y0 > c_ymin:
                    FLAG = True
                    writer.writerow([box.Class, b_xmin, b_xmax, b_ymin, b_ymax, box.probability, odom.pose.pose.position.x, odom.pose.pose.position.y])
                    img = bridge. imgmsg_to_cv2(image, "bgr8")
                    cv2.imwrite("/home/ryken/Desktop/real/src/object_detection/results/"+box.Class+".jpeg", img)
                else:
                    FLAG = False
            else:
                writer.writerow(row)
                
        if not FLAG:
            writer.writerow([box.Class, b_xmin, b_xmax, b_ymin, b_ymax, box.probability, odom.pose.pose.position.x, odom.pose.pose.position.y])
            img = bridge. imgmsg_to_cv2(image, "bgr8")
            cv2.imwrite("/home/ryken/Desktop/real/src/object_detection/results/"+box.Class+".jpeg", img)

def callback(boxes, image, odom):
    for box in boxes.bounding_boxes:
        if box.probability >= 0.7:
            new_object(box, image, odom)
    
if __name__ == '__main__':
    
    with open("/home/ryken/Desktop/real/src/object_detection/buffer/buffer.csv", "w") as file_out:
        writer = csv.writer(file_out)
    
    rospy.init_node('object_detection')
    
    bridge = CvBridge()
    
    boxes = Subscriber("darknet_ros/bounding_boxes", BoundingBoxes, queue_size=1)
    image = Subscriber("darknet_ros/detection_image", Image, queue_size=1)
    odom = Subscriber("odom", Odometry, queue_size=1)
    ts = ApproximateTimeSynchronizer([boxes, image, odom], 5, 0.2, allow_headerless=False)
    ts.registerCallback(callback)
    
    try:
        rospy.loginfo("Started Object Detection...")
        rospy.spin()
    except rospy.ROSInterruptException:
        rospy.loginfo("Shutting down Object Detection...")
