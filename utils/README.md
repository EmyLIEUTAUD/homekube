## Script permettant la suppression d'un namespace bloqué en "Terminating"
Utilisation : 
```bash
sh force_delete_namespace.sh <nom-du-namespace>
```

Ce que fait le script : 
1. Démarre un proxy local vers l'API Kube (à 127.0.0.1:8001)
2. Récupère la définition JSON complète du namespace
3. Modifie la section spec.finalizers pour la vider
4. Envoie cette nouvelle définition via une requête PUT sur l'endpoint /finalize
> Le namespace est alors immédiatement supprimé

> **Attention**
> Ce script force la suppression d'un namespace sans attendre que les ressources soient nettoyées proprement.
> A utiliser en dernier recours uniquement
