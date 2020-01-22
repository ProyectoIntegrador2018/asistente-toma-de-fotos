//
//  EditorViewController.swift
//  Azul
//
//  Created by German Villacorta on 1/21/20.
//  Copyright © 2020 Azul. All rights reserved.
//

import UIKit

class EditorViewController: UIViewController {

    var imageData: Data?
    
    @IBOutlet weak var currentImage: UIImageView!
    override func viewDidLoad() {
        super.viewDidLoad()
        
        currentImage.image = UIImage(data: self.imageData!)
        // Do any additional setup after loading the view.
    }
    

    @IBAction func cancel(_ sender: Any) {
        self.dismiss(animated: false, completion: nil)
    }
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
