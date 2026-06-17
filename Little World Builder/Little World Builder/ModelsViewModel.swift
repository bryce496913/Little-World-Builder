//
//  ModelsViewModel.swift
//  AR Test
//
//  Created by Bryce on 27/08/21.
//

import Combine
import FirebaseFirestore

final class ModelsViewModel: ObservableObject {
    @Published var models: [Model] = []
    
    private let db = Firestore.firestore()
    
    func fetchData() {
        db.collection("models").addSnapshotListener { querySnapshot, error in
            if let error = error {
                print("Firestore Error: Unable to fetch models: \(error.localizedDescription)")
                return
            }

            guard let documents = querySnapshot?.documents else {
                print("Firestore: No model documents returned.")
                return
            }
            
            self.models = documents.map { queryDocumentSnapshot -> Model in
                let data = queryDocumentSnapshot.data()
                
                let name = data["name"] as? String ?? ""
                let categoryText = data["category"] as? String ?? ""
                let category = ModelCategory(rawValue: categoryText) ?? .land
                
                return Model(name: name, category: category)
            }
        }
    }
    
    func clearModelEntitiesFromMemory() {
        for model in models {
            model.modelEntity = nil
        }
    }
}
