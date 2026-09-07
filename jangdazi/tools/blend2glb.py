import bpy, sys
out = sys.argv[-1]
print("OBJECTS:")
for o in bpy.data.objects:
    print("  ", o.type, o.name, [round(v,2) for v in o.dimensions] if o.type=='MESH' else "", "parent=", o.parent.name if o.parent else None)
print("ARMATURES:", [(a.name, len(a.bones)) for a in bpy.data.armatures])
print("ACTIONS:", [(a.name, round(a.frame_range[1]-a.frame_range[0])) for a in bpy.data.actions])
print("IMAGES:", [(i.name, i.size[0], i.filepath) for i in bpy.data.images][:40])
print("MATERIALS:", [m.name for m in bpy.data.materials])
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_animations=True, export_apply=True, export_image_format='AUTO', export_texcoords=True, export_normals=True, export_materials='EXPORT', export_yup=True)
print("EXPORTED", out)
