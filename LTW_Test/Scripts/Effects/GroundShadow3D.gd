class_name GroundShadow3D
extends MeshInstance3D

## The disc drawn on the ground under a FLYING creep.
##
## It is what makes flying readable. A top down camera sees almost none of the
## height a flyer is actually at, so altitude on its own says nothing: a Shade
## hanging at cruising height and a Shade standing on the floor are the same
## picture. The disc is pinned to the ground below the creep, so what the
## player sees instead is a shadow with nothing standing on it.
##
## A CLASS WITH NO CODE IN IT, and that is the whole job. Two things need to
## know that this mesh is not part of the creature - the portrait and the baked
## icon, both through VisualUtil - and a type is the only way to tell them that
## cannot be broken by renaming a node in a generated scene. It is the same
## reasoning BuildingFoundation is a class rather than a node name.
##
## Written by Tools/ModelGen onto every flying creep's model. Nothing creates
## one at runtime.
