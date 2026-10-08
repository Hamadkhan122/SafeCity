# Screen-texture model, part 2: small CNN (117k parameters) + TFLite export -> ../safecity/assets/models/screen_texture.tflite
# Test: about 1.4% of held-out real photos score >= 0.90 (app threshold), 0.3% >= 0.95.
import numpy as np, tensorflow as tf
tr=np.load("tex_train.npz"); va=np.load("tex_val.npz")
Xtr,ytr,Xva,yva=tr["X"],tr["y"].astype(np.float32),va["X"],va["y"].astype(np.float32)
def aug(x,y):
    x=tf.image.random_flip_left_right(x); x=tf.image.random_flip_up_down(x)
    x=tf.image.rot90(x,tf.random.uniform([],0,4,tf.int32))
    x=tf.cast(x,tf.float32); x=tf.image.random_brightness(x,25.); x=tf.image.random_contrast(x,.8,1.2)
    return tf.clip_by_value(x,0,255),y
dtr=tf.data.Dataset.from_tensor_slices((Xtr,ytr)).shuffle(20000).map(aug,num_parallel_calls=4).batch(64).prefetch(2)
dva=tf.data.Dataset.from_tensor_slices((Xva.astype(np.float32),yva)).batch(128)
L=tf.keras.layers
inp=tf.keras.Input((128,128,3),name="patch"); x=L.Rescaling(1/255.)(inp)
for f,s in [(16,1),(16,2),(32,1),(32,2),(48,1),(48,2),(64,1),(64,2)]:
    x=L.Conv2D(f,3,strides=s,padding="same",use_bias=False)(x); x=L.BatchNormalization()(x); x=L.ReLU()(x)
x=L.GlobalAveragePooling2D()(x); x=L.Dropout(.2)(x); out=L.Dense(1,activation="sigmoid",name="screen_texture")(x)
m=tf.keras.Model(inp,out)
m.compile(tf.keras.optimizers.Adam(2e-3),"binary_crossentropy",metrics=[tf.keras.metrics.AUC(name="auc"),"accuracy"])
m.fit(dtr,validation_data=dva,epochs=12,verbose=2,callbacks=[tf.keras.callbacks.ReduceLROnPlateau(patience=2,factor=.4),tf.keras.callbacks.EarlyStopping(patience=4,restore_best_weights=True)])
m.save("tex_model.keras"); print("params",m.count_params())
c=tf.lite.TFLiteConverter.from_keras_model(m); open("../safecity/assets/models/screen_texture.tflite","wb").write(c.convert())
